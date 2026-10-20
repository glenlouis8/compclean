import Foundation
import Testing
@testable import CleanerCore

@Suite struct LeftoverFinderTests {
    func fakeApp(in h: FakeHome) throws -> AppInfo {
        let url = try h.dir("Applications/Foo Bar.app")
        return AppInfo(url: url, name: "Foo Bar", bundleID: "com.foocorp.foobar", version: "1.0",
                       teamID: "ABCDE12345", isApple: false)
    }

    @Test func findsLeftoversAndSkipsOthers() throws {
        let h = try FakeHome()
        let app = try fakeApp(in: h)
        try h.file("Library/Preferences/com.foocorp.foobar.plist")
        try h.file("Library/Preferences/ByHost/com.foocorp.foobar.1234-5678.plist")
        try h.dir("Library/Application Support/Foo Bar")
        try h.dir("Library/Caches/com.foocorp.foobar")
        try h.dir("Library/Containers/com.foocorp.foobar")
        try h.dir("Library/Group Containers/ABCDE12345.com.foocorp.shared")
        try h.dir("Library/Saved Application State/com.foocorp.foobar.savedState")
        try h.file("Library/LaunchAgents/com.foocorp.updater.plist")
        // Not this app's files.
        try h.file("Library/Preferences/com.apple.finder.plist")
        try h.file("Library/Preferences/com.other.app.plist")
        try h.dir("Library/Application Support/Foo")

        let finder = LeftoverFinder(policy: h.policy, systemLibrary: h.url.appendingPathComponent("nosystem"),
                                    readReceipts: false)
        let leftovers = finder.find(for: app)
        let found = Dictionary(leftovers.map { ($0.url.lastPathComponent, $0.match) }, uniquingKeysWith: { a, _ in a })
        #expect(leftovers.filter { $0.url.lastPathComponent == "com.foocorp.foobar" }.count == 2)

        #expect(found["Foo Bar.app"] == .app)
        #expect(found["com.foocorp.foobar.plist"] == .bundleID)
        #expect(found["com.foocorp.foobar.1234-5678.plist"] == .bundleID)
        #expect(found["Foo Bar"] == .appName)
        #expect(found["com.foocorp.foobar.savedState"] == .bundleID)
        #expect(found["ABCDE12345.com.foocorp.shared"] == .team)
        #expect(found["com.foocorp.updater.plist"] == .company)
        #expect(found["com.apple.finder.plist"] == nil)
        #expect(found["com.other.app.plist"] == nil)
        #expect(found["Foo"] == nil)
        #expect(MatchKind.team.preselected == false && MatchKind.company.preselected == false)
    }

    @Test func appleAppGetsNothing() throws {
        let h = try FakeHome()
        let url = try h.dir("Applications/Notes.app")
        let app = AppInfo(url: url, name: "Notes", bundleID: "com.apple.Notes", version: nil, teamID: nil, isApple: true)
        #expect(LeftoverFinder(policy: h.policy, readReceipts: false).find(for: app).isEmpty)
    }
}

@Suite struct ScannerTests {
    @Test func scansOnlySafeItems() throws {
        let h = try FakeHome()
        try h.file("Library/Caches/com.spotify.client/data", bytes: 4096)
        try h.file("Library/Caches/com.apple.Safari/data", bytes: 4096)
        try h.file("Library/Caches/CloudKit/data", bytes: 4096)
        try h.file("Library/Caches/com.slack.app/Cookies", bytes: 4096)
        try h.file("Library/Caches/com.running.app/data", bytes: 4096)
        try h.file("Library/Application Support/Google/Chrome/Default/Cache/x", bytes: 4096)
        try h.file("Library/Application Support/Google/Chrome/Default/Cookies", bytes: 4096)
        try h.file("Library/Caches/Homebrew/pkg.tar.gz", bytes: 4096)

        let scanner = Scanner(policy: h.policy, runningBundleIDs: ["com.running.app"])
        let found = scanner.scan(Set(CleanCategory.allCases))
        let paths = Set(found.map { $0.url.path.replacingOccurrences(of: h.policy.home + "/", with: "") })

        #expect(paths.contains("Library/Caches/com.spotify.client"))
        #expect(paths.contains("Library/Application Support/Google/Chrome/Default/Cache"))
        #expect(paths.contains("Library/Caches/Homebrew"))
        #expect(!paths.contains { $0.contains("com.apple") || $0.contains("CloudKit") })
        #expect(!paths.contains("Library/Caches/com.slack.app"))
        #expect(!paths.contains("Library/Caches/com.running.app"))
        #expect(!paths.contains { $0.contains("Cookies") })
        #expect(found.first { $0.url.lastPathComponent == "Homebrew" }?.category == .devCaches)
    }

    @Test func trasherRefusesOutsidePolicy() throws {
        let h = try FakeHome()
        let protected = try h.file("Library/Cookies/Cookies.binarycookies")
        let log = ActionLog(url: h.url.appendingPathComponent("log.txt"))
        let outcome = Trasher(policy: h.policy, log: log).trash([(protected, 16)], purpose: .clean)
        #expect(outcome.trashed.isEmpty)
        #expect(outcome.refused.count == 1)
        #expect(FileManager.default.fileExists(atPath: protected.path))
    }

    @Test func adminScriptQuotesPaths() {
        let url = URL(fileURLWithPath: "/Library/LaunchDaemons/com.x'; rm -rf ~; '.plist")
        let dests = PrivilegedRemover.destinations(for: [url], home: "/Users/test")
        let script = PrivilegedRemover.script(for: [url], dests: dests, uid: 501)
        #expect(script.contains("'/Library/LaunchDaemons/com.x'\\''; rm -rf ~; '\\''.plist'"))
    }
}
