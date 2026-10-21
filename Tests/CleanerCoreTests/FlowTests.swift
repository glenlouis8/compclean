import Foundation
import Testing
@testable import CleanerCore

/// A fake home that looks like a real one: junk to clean, plus files that must never be touched.
/// Every flow test runs the real finders and removers against it, with a fake Trash,
/// then checks every protected file is still there, byte for byte.
final class SeededHome {
    let h: FakeHome
    var policy: SafetyPolicy { h.policy }
    var url: URL { h.url }
    let log: ActionLog
    let ledger: TrashLedger
    private(set) var protected: [String: Data] = [:]

    static let protectedFiles = [
        "Library/Cookies/Cookies.binarycookies",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Google/Chrome/Default/Login Data",
        "Library/Application Support/Google/Chrome/Default/History",
        "Library/Application Support/Google/Chrome/Default/Bookmarks",
        "Library/Application Support/Google/Chrome/Default/Preferences",
        "Library/Application Support/Google/Chrome/Default/Local Storage/leveldb/000003.log",
        "Library/Application Support/Firefox/Profiles/x.default/places.sqlite",
        "Library/Application Support/Firefox/Profiles/x.default/cookies.sqlite",
        "Library/Keychains/login.keychain-db",
        "Library/Caches/com.apple.Safari/Cache.db",
        "Library/Caches/CloudKit/data.db",
        "Library/Preferences/com.apple.finder.plist",
        "Library/Preferences/org.cups.PrintingPrefs.plist",
        "Library/Application Scripts/group.is.workflow.my.app/x",
        "Library/Mail/V10/inbox.emlx",
        "Library/Mobile Documents/com~apple~CloudDocs/notes.pages",
        "Library/LaunchAgents/homebrew.mxcl.redis.plist",
        "Library/Preferences/org.sparkle-project.Sparkle.Autoupdate.plist",
        "Documents/thesis.docx",
        "Desktop/photo.jpg",
        "Coding/oldsite/package.json",
        "Coding/oldsite/src/index.js",
        "Coding/active/package.json",
        "Coding/active/node_modules/react/index.js",
        "Library/Application Support/com.foo.app/keep-if-not-uninstalling.db",
    ]

    static let junk = [
        "Library/Caches/com.spotify.client/data",
        "Library/Application Support/Google/Chrome/Default/Cache/Cache_Data/f_000001",
        "Library/Logs/com.spotify.client/old.log",
        ".npm/_cacache/index-v5/aa",
        "Library/Preferences/com.gone.app.plist",
        "Library/Application Support/com.gone.app/state.json",
        "Coding/oldsite/node_modules/lodash/index.js",
    ]

    init() throws {
        h = try FakeHome()
        log = ActionLog(url: h.url.appendingPathComponent("../actions.log"))
        ledger = TrashLedger(home: h.policy.home, url: h.url.appendingPathComponent("../history.json"))
        try h.dir(".Trash")

        for rel in Self.protectedFiles {
            let u = try h.file(rel, bytes: 64)
            try Data("protected:\(rel)".utf8).write(to: u)
        }
        for rel in Self.junk { try Data("junk:\(rel)".utf8).write(to: try h.file(rel)) }

        try h.file("Downloads/old-installer.dmg", bytes: 2048)
        try age("Downloads/old-installer.dmg", days: 200)
        try age("Library/Logs/com.spotify.client/old.log", days: 30)
        try age("Coding/oldsite/package.json", days: 120)
        try age("Coding/oldsite/src/index.js", days: 120)
        try age("Coding/active/package.json", days: 1)

        // An installed app with its own leftovers.
        let app = try h.dir("Applications/Foo.app/Contents/MacOS")
        let info: NSDictionary = ["CFBundleIdentifier": "com.foo.app", "CFBundleName": "Foo", "CFBundleExecutable": "Foo"]
        info.write(to: app.deletingLastPathComponent().appendingPathComponent("Info.plist"), atomically: true)
        try Data("binary".utf8).write(to: app.appendingPathComponent("Foo"))
        try Data("prefs".utf8).write(to: try h.file("Library/Preferences/com.foo.app.plist"))
        try Data("box".utf8).write(to: try h.file("Library/Containers/com.foo.app/Data/x"))
        // Another installed app's settings, never part of Foo's uninstall.
        try Data("bar".utf8).write(to: try h.file("Library/Preferences/com.bar.app.plist"))

        for rel in Self.protectedFiles { protected[rel] = try Data(contentsOf: h.url.appendingPathComponent(rel)) }
    }

    func age(_ rel: String, days: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-days * 86_400)],
                                              ofItemAtPath: h.url.appendingPathComponent(rel).path)
    }

    func trasher() throws -> Trasher { try h.trasher(log: log) }

    var fakeMover: @Sendable (URL) throws -> URL? { (try? trasher().mover) ?? Trasher.systemTrash }

    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: h.url.appendingPathComponent(rel).path) }

    func rel(_ url: URL) -> String {
        let p = SafetyPolicy.realPath(url.path) ?? url.path
        return p.replacingOccurrences(of: policy.home + "/", with: "")
    }

    /// Every protected file still exists with its original bytes.
    func expectProtectedUntouched(_ step: String, sourceLocation: SourceLocation = #_sourceLocation) {
        for (rel, data) in protected {
            let now = try? Data(contentsOf: h.url.appendingPathComponent(rel))
            #expect(now == data, "\(step): protected file changed or gone: \(rel)", sourceLocation: sourceLocation)
        }
    }

    func putBackAll(_ session: LedgerSession) {
        for e in session.entries {
            let r = ledger.putBack(e)
            if case .restored = r { continue }
            Issue.record("put back failed for \(e.original): \(r)")
        }
    }
}

@Suite struct FullFlowTests {
    @Test func cleanerScanTrashPutBack() throws {
        let s = try SeededHome()
        // Pretend it's 200 days from now: a file made today can't look old to macOS otherwise.
        let found = Scanner(policy: s.policy, now: Date().addingTimeInterval(200 * 86_400)).scan(Set(CleanCategory.allCases))
        let foundRel = Set(found.map { s.rel($0.url) })
        #expect(foundRel.isDisjoint(with: SeededHome.protectedFiles), "scanner offered protected files")
        #expect(foundRel.contains("Library/Caches/com.spotify.client"))
        #expect(foundRel.contains("Downloads/old-installer.dmg"))

        // Trash everything the scanner found, even the manual-only items.
        let outcome = try s.trasher().trash(found)
        #expect(outcome.refused.isEmpty && outcome.failed.isEmpty)
        #expect(!s.exists("Library/Caches/com.spotify.client"))
        #expect(!s.exists("Library/Application Support/Google/Chrome/Default/Cache"))
        s.expectProtectedUntouched("after clean")

        let session = try #require(s.ledger.record(feature: "Cleaner", moves: outcome.moves))
        s.putBackAll(session)
        #expect(try String(contentsOf: s.url.appendingPathComponent("Library/Caches/com.spotify.client/data"), encoding: .utf8)
                == "junk:Library/Caches/com.spotify.client/data")
        #expect(s.exists("Downloads/old-installer.dmg"))
        #expect(s.ledger.sessions()[0].entries.allSatisfy { s.ledger.status(of: $0) == .restored })
        s.expectProtectedUntouched("after put back")
    }

    @Test func autoCleanSkipsManualCategoriesAndRunningApps() throws {
        let s = try SeededHome()
        let scanner = Scanner(policy: s.policy, runningBundleIDs: ["com.spotify.client"])
        let run = try AutoCleaner(scanner: scanner, trasher: s.trasher(), explainer: ItemExplainer(home: s.policy.home)).run()
        #expect(!run.outcome.moves.isEmpty)
        #expect(s.exists("Downloads/old-installer.dmg"), "auto clean must never touch Downloads")
        #expect(s.exists("Library/Caches/com.spotify.client/data"), "running app's cache must be skipped")
        #expect(s.exists("Library/Logs/com.spotify.client/old.log"), "running app's logs must be skipped")
        #expect(!s.exists(".npm/_cacache"))
        #expect(run.titles.values.allSatisfy { !$0.isEmpty })
        s.expectProtectedUntouched("after auto clean")
    }

    @Test func scheduleIsDue() {
        let now = Date()
        // Never cleans on first launch: no last run means it hasn't started counting.
        #expect(!Schedule.daily.isDue(lastRun: nil, now: now))
        #expect(Schedule.defaultValue == .off)
        #expect(!Schedule.daily.isDue(lastRun: now.addingTimeInterval(-3_600), now: now))
        #expect(Schedule.daily.isDue(lastRun: now.addingTimeInterval(-90_000), now: now))
        #expect(!Schedule.weekly.isDue(lastRun: now.addingTimeInterval(-3 * 86_400), now: now))
        #expect(!Schedule.off.isDue(lastRun: nil, now: now))
    }

    @Test func uninstallRemovesAppAndOnlyItsFiles() throws {
        let s = try SeededHome()
        let app = try #require(AppInspector.inspect(s.url.appendingPathComponent("Applications/Foo.app")))
        #expect(app.bundleID == "com.foo.app" && !app.isApple)

        let finder = LeftoverFinder(policy: s.policy, systemLibrary: s.url.appendingPathComponent("no-system-library"),
                                    readReceipts: false)
        let leftovers = finder.find(for: app)
        #expect(leftovers.allSatisfy { !$0.needsAdmin })
        let names = Set(leftovers.map(\.url.lastPathComponent))
        #expect(names.isSuperset(of: ["Foo.app", "com.foo.app.plist", "com.foo.app"]))
        #expect(!names.contains("com.bar.app.plist"))

        let report = Uninstaller(policy: s.policy, log: s.log, mover: s.fakeMover, allowAdmin: false)
            .remove(leftovers.filter(\.match.preselected), of: app)
        #expect(report.failed.isEmpty && !report.adminCancelled)
        #expect(!s.exists("Applications/Foo.app"))
        #expect(!s.exists("Library/Preferences/com.foo.app.plist"))
        #expect(!s.exists("Library/Containers/com.foo.app"),
                "found: \(leftovers.map { "\(s.rel($0.url)) [\($0.match)]" }), moved: \(report.moves.map { s.rel($0.from) })")
        #expect(s.exists("Library/Preferences/com.bar.app.plist"), "another app's settings were removed")

        // Foo's own Application Support folder was one of its leftovers, so it's not in this check.
        for (rel, data) in s.protected where !rel.contains("com.foo.app") {
            #expect((try? Data(contentsOf: s.url.appendingPathComponent(rel))) == data, "protected file changed: \(rel)")
        }

        let session = try #require(s.ledger.record(feature: "Uninstalled Foo", moves: report.moves))
        s.putBackAll(session)
        #expect(s.exists("Applications/Foo.app/Contents/Info.plist"))
        #expect(AppInspector.inspect(s.url.appendingPathComponent("Applications/Foo.app"))?.bundleID == "com.foo.app")
        s.expectProtectedUntouched("after put back")
    }

    @Test func leftoversOfDeletedAppsOnly() throws {
        let s = try SeededHome()
        let items = OrphanFinder(policy: s.policy, knownIDs: ["com.foo.app", "com.bar.app", "com.spotify.client"],
                                 isRegistered: { _ in false }).find()
        let rels = Set(items.map { s.rel($0.url) })
        #expect(rels == ["Library/Preferences/com.gone.app.plist", "Library/Application Support/com.gone.app"], "got \(rels)")

        let outcome = try s.trasher().trash(items)
        #expect(outcome.moves.count == 2)
        s.expectProtectedUntouched("after leftovers")
    }

    @Test func devJunkOnlyStaleDependencies() throws {
        let s = try SeededHome()
        let items = DevJunkFinder(policy: s.policy, roots: [s.url.appendingPathComponent("Coding")]).find()
        #expect(items.map { s.rel($0.url) } == ["Coding/oldsite/node_modules"])
        _ = try s.trasher().trash(items)
        #expect(!s.exists("Coding/oldsite/node_modules"))
        #expect(s.exists("Coding/oldsite/src/index.js") && s.exists("Coding/oldsite/package.json"))
        s.expectProtectedUntouched("after dev junk")
    }

    @Test func duplicatesKeepOneCopy() throws {
        let s = try SeededHome()
        let original = try s.h.file("Documents/report.pdf", bytes: 1_200_000)
        let copy = s.url.appendingPathComponent("Downloads/report (1).pdf")
        try Data(contentsOf: original).write(to: copy)

        let items = DuplicateFinder(policy: s.policy).find()
        #expect(items.count == 2 && items.filter(\.isKeeper).count == 1)
        _ = try s.trasher().trash(items.filter { !$0.isKeeper })
        let remaining = [original, copy].filter { FileManager.default.fileExists(atPath: $0.path) }
        #expect(remaining.count == 1, "exactly one copy must remain")
        s.expectProtectedUntouched("after duplicates")
    }

    /// Last line of defence: even if a finder had a bug and offered protected files,
    /// the Trasher must refuse them.
    @Test func trasherRefusesProtectedFiles() throws {
        let s = try SeededHome()
        let trasher = try s.trasher()
        func sweep(_ rels: [String], _ purpose: Purpose) {
            let outcome = trasher.trash(rels.map { (url: s.url.appendingPathComponent($0), size: Int64(64)) }, purpose: purpose)
            #expect(outcome.moves.isEmpty, "\(purpose) moved: \(outcome.moves.map { s.rel($0.from) })")
        }
        // Cleaning and Downloads review never touch any of them.
        sweep(SeededHome.protectedFiles, .clean)
        sweep(SeededHome.protectedFiles, .reviewDownloads)
        sweep(SeededHome.protectedFiles, .devProjects)
        // Your own files are fair game for big files and duplicates, so only check everything else.
        sweep(SeededHome.protectedFiles.filter { !["Documents/", "Desktop/", "Coding/"].contains(where: $0.hasPrefix) }, .userFiles)
        // Uninstall may remove an app's own data (that's the point); macOS and Apple items never.
        sweep(SeededHome.protectedFiles.filter {
            $0.contains("com.apple") || $0.contains("org.cups") || $0.contains("is.workflow")
                || $0.hasPrefix("Library/Keychains") || $0.hasPrefix("Library/Mail") || $0.contains("Mobile Documents")
        }, .uninstall)
        s.expectProtectedUntouched("after refusal sweep")
    }
}
