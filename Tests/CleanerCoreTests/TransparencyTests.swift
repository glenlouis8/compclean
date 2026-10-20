import Foundation
import Testing
@testable import CleanerCore

extension FakeHome {
    /// Trasher that moves into a fake Trash inside this home instead of the real one.
    func trasher(log: ActionLog) throws -> Trasher {
        let trash = try dir(".Trash")
        return Trasher(policy: policy, log: log, mover: { url in
            let dest = trash.appendingPathComponent(url.lastPathComponent + " \(UUID().uuidString.prefix(4))")
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        })
    }
}

@Suite struct HistoryProtectionTests {
    @Test(arguments: [
        "Library/Caches/com.foo.browser/History",
        "Library/Caches/com.foo.browser/Bookmarks",
        "Library/Caches/com.foo.browser/Favicons",
        "Library/Caches/com.foo.browser/Top Sites",
        "Library/Application Support/Google/Chrome/Default/History",
        "Library/Application Support/Google/Chrome/Default/Preferences",
    ])
    func historyFilesRefused(_ rel: String) throws {
        let h = try FakeHome()
        let u = try h.file(rel)
        #expect(!h.policy.canTrash(u, for: .clean))
        // The folder holding it is refused as a whole too.
        #expect(!h.policy.canTrash(u.deletingLastPathComponent(), for: .clean))
    }
}

@Suite struct NewPurposeTests {
    @Test func devProjectsNeedMarkers() throws {
        let h = try FakeHome()
        try h.file("Coding/web/package.json")
        let nm = try h.dir("Coding/web/node_modules")
        let orphanNM = try h.dir("Coding/notaproject/node_modules")
        try h.file("Coding/py/.venv/pyvenv.cfg")
        try h.file("Coding/rs/Cargo.toml")
        let target = try h.dir("Coding/rs/target")
        let fakeTarget = try h.dir("Coding/movies/target")
        let nested = try h.dir("Coding/web/node_modules/pkg/node_modules")
        try h.file("Coding/web/node_modules/pkg/package.json")
        let libNM = try h.dir("Library/Application Support/Foo/node_modules")
        try h.file("Library/Application Support/Foo/package.json")

        #expect(h.policy.canTrash(nm, for: .devProjects))
        #expect(h.policy.canTrash(h.url.appendingPathComponent("Coding/py/.venv"), for: .devProjects))
        #expect(h.policy.canTrash(target, for: .devProjects))
        #expect(!h.policy.canTrash(orphanNM, for: .devProjects))
        #expect(!h.policy.canTrash(fakeTarget, for: .devProjects))
        #expect(!h.policy.canTrash(nested, for: .devProjects))
        #expect(!h.policy.canTrash(libNM, for: .devProjects))
        #expect(!h.policy.canTrash(h.url.appendingPathComponent("Coding/web"), for: .devProjects))
    }

    @Test func userFilesRules() throws {
        let h = try FakeHome()
        #expect(h.policy.canTrash(try h.file("Downloads/big.dmg"), for: .userFiles))
        #expect(h.policy.canTrash(try h.file("Movies/old/clip.mov"), for: .userFiles))
        #expect(h.policy.canTrash(try h.file("loose.zip"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.dir("Documents"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.file("Library/thing.bin"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.file(".ssh/id_rsa"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.file("Code/proj/.git/objects/pack.pack"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.file("Pictures/Photos Library.photoslibrary/originals/a.heic"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.dir("Pictures/Photos Library.photoslibrary"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.file("Library/Mobile Documents/com~apple~CloudDocs/a.pdf"), for: .userFiles))
        #expect(!h.policy.canTrash(try h.dir("Applications/Foo.app"), for: .userFiles))
    }
}

@Suite struct LedgerTests {
    @Test func trashThenPutBack() throws {
        let h = try FakeHome()
        let log = ActionLog(url: h.url.appendingPathComponent("log.txt"))
        let item = try h.file("Library/Caches/com.spotify.client/data", bytes: 64)
        let folder = item.deletingLastPathComponent()
        let outcome = try h.trasher(log: log).trash([(folder, 64)], purpose: .clean)
        #expect(outcome.moves.count == 1)
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        let ledger = TrashLedger(home: h.policy.home, url: h.url.appendingPathComponent("history.json"))
        let session = try #require(ledger.record(feature: "Cleaner", moves: outcome.moves, titles: [folder: "Spotify · cache"]))
        #expect(ledger.sessions().first?.entries.first?.title == "Spotify · cache")
        #expect(ledger.status(of: session.entries[0]) == .inTrash)

        guard case .restored(let dest) = ledger.putBack(session.entries[0]) else {
            Issue.record("not restored"); return
        }
        #expect(SafetyPolicy.realPath(dest.path) == h.policy.home + "/Library/Caches/com.spotify.client")
        #expect(FileManager.default.fileExists(atPath: h.policy.home + "/Library/Caches/com.spotify.client/data"))
        #expect(ledger.status(of: ledger.sessions()[0].entries[0]) == .restored)
    }

    @Test func putBackRenamesOnClash() throws {
        let h = try FakeHome()
        let log = ActionLog(url: h.url.appendingPathComponent("log.txt"))
        let file = try h.file("Downloads/report.pdf")
        let outcome = try h.trasher(log: log).trash([(file, 16)], purpose: .reviewDownloads)
        try h.file("Downloads/report.pdf") // a new file took the name
        let ledger = TrashLedger(home: h.policy.home, url: h.url.appendingPathComponent("history.json"))
        let session = try #require(ledger.record(feature: "Cleaner", moves: outcome.moves))
        guard case .restored(let dest) = ledger.putBack(session.entries[0]) else {
            Issue.record("not restored"); return
        }
        #expect(dest.lastPathComponent == "report (restored).pdf")
    }

    @Test func emptiedTrashIsGone() throws {
        let h = try FakeHome()
        let ledger = TrashLedger(home: h.policy.home, url: h.url.appendingPathComponent("history.json"))
        let move = Move(from: h.url.appendingPathComponent("x"), to: h.url.appendingPathComponent(".Trash/x"), size: 1)
        let session = try #require(ledger.record(feature: "Cleaner", moves: [move]))
        #expect(ledger.status(of: session.entries[0]) == .emptied)
        #expect(ledger.putBack(session.entries[0]) == .gone)
    }

    @Test func adminPutBackOnlyIntoThirdPartyFolders() {
        #expect(PrivilegedRemover.isRestorable(URL(fileURLWithPath: "/Applications/Foo.app")))
        #expect(PrivilegedRemover.isRestorable(URL(fileURLWithPath: "/Library/LaunchDaemons/com.foo.helper.plist")))
        #expect(!PrivilegedRemover.isRestorable(URL(fileURLWithPath: "/System/Library/foo")))
        #expect(!PrivilegedRemover.isRestorable(URL(fileURLWithPath: "/Library/LaunchDaemons/com.apple.x.plist")))
        #expect(!PrivilegedRemover.isRestorable(URL(fileURLWithPath: "/usr/local/bin/foo")))
        #expect(!PrivilegedRemover.isRestorable(URL(fileURLWithPath: "/Applications/Utilities/Foo.app")))
    }
}

@Suite struct ExplainerTests {
    @Test func plainLanguage() throws {
        let h = try FakeHome()
        let e = ItemExplainer(home: h.policy.home)
        let cache = Finding(url: try h.dir("Library/Caches/BraveSoftware"), size: 1, category: .userCaches)
        let x = e.explain(cache)
        #expect(x.title.hasPrefix("Brave"))
        #expect(x.safety == .rebuildsItself)
        let npm = Finding(url: try h.dir(".npm/_cacache"), size: 1, category: .devCaches)
        #expect(e.explain(npm).title == "npm download cache")
        let dl = Finding(url: try h.file("Downloads/a.zip"), size: 1, category: .oldDownloads)
        #expect(e.explain(dl).safety == .yourFile)
        #expect(ItemExplainer.guessName(fromBundleID: "com.spotify.client") == "Spotify")
        #expect(ItemExplainer.guessName(fromBundleID: "app.monitorcontrol.MonitorControl") == "MonitorControl")
        #expect(ItemExplainer.guessName(fromBundleID: "com.macpaw.CleanMyMac-mas") == "CleanMyMac by Macpaw")
        #expect(ItemExplainer.guessName(fromBundleID: "ru.keepcoder.Telegram") == "Telegram by Keepcoder")
        #expect(ItemExplainer.guessName(fromBundleID: "com.adguard.safari.AdGuard") == "AdGuard")
        #expect(ItemExplainer.guessName(fromBundleID: "com.adobe.NGL") == "NGL by Adobe")
        #expect(ItemExplainer.guessName(fromBundleID: "com.openai.chat") == "Openai")
    }
}
