import Foundation
import Testing
@testable import CleanerCore

@Suite struct OrphanFinderTests {
    func finder(_ h: FakeHome, installed: Set<String>) -> OrphanFinder {
        OrphanFinder(policy: h.policy, knownIDs: installed, isRegistered: { _ in false },
                     now: Date().addingTimeInterval(60 * 86_400))
    }

    @Test func findsDeletedAppLeftovers() throws {
        let h = try FakeHome()
        try h.dir("Library/Application Support/com.spotify.client")
        try h.file("Library/Preferences/com.spotify.client.plist")
        try h.dir("Library/Caches/com.spotify.client")
        try h.dir("Library/Saved Application State/com.spotify.client.savedState")
        try h.dir("Library/Group Containers/ABCDE12345.com.spotify.shared")
        try h.file("Library/Preferences/ByHost/com.spotify.client.0123ABCD-4567-89EF-0123-456789ABCDEF.plist")

        let items = finder(h, installed: []).find()
        let names = Set(items.map(\.url.lastPathComponent))
        #expect(names.contains("com.spotify.client"))
        #expect(names.contains("com.spotify.client.plist"))
        #expect(names.contains("com.spotify.client.savedState"))
        #expect(names.contains("ABCDE12345.com.spotify.shared"))
        #expect(names.contains("com.spotify.client.0123ABCD-4567-89EF-0123-456789ABCDEF.plist"))
        #expect(items.allSatisfy { $0.explanation.safety == .leftover && $0.purpose == .uninstall })
        #expect(items.first?.group == "Spotify (not installed)")
    }

    @Test func skipsInstalledHelpersAndVendors() throws {
        let h = try FakeHome()
        try h.file("Library/Preferences/com.microsoft.autoupdate2.plist") // vendor of an installed app
        try h.file("Library/Preferences/com.docker.docker.helper.plist")  // helper of an installed app
        try h.dir("Library/Caches/com.raycast.macos")                      // installed
        try h.file("Library/Preferences/com.apple.finder.plist")           // Apple
        try h.dir("Library/Application Support/Foo")                       // plain name: not judged
        try h.file("Library/LaunchAgents/homebrew.mxcl.redis.plist")       // Homebrew service
        try h.file("Library/Preferences/org.cups.PrintingPrefs.plist")     // macOS printing
        try h.dir("Library/Application Scripts/group.is.workflow.my.app")  // Apple Shortcuts
        try h.file("Library/Preferences/org.sparkle-project.Sparkle.Autoupdate.plist") // shared updater
        try h.file("Library/Preferences/com.segment.storage.oai.plist")    // analytics SDK
        try h.dir("Library/Caches/org.swift.swiftpm")                      // command-line tool
        try h.dir("Library/Application Scripts/UBF8T346G9.com.microsoft.teams") // team prefix + installed vendor
        let items = finder(h, installed: ["com.microsoft.VSCode", "com.docker.docker", "com.raycast.macos"]).find()
        #expect(items.isEmpty, "unexpected: \(items.map(\.url.lastPathComponent))")
    }

    @Test func registeredAppsAreNotOrphans() throws {
        let h = try FakeHome()
        try h.dir("Library/Caches/org.python.python")
        let f = OrphanFinder(policy: h.policy, knownIDs: [], isRegistered: { $0 == "org.python.python" })
        #expect(f.find().isEmpty)
    }

    @Test func launchAgentWithLiveProgramIsKept() throws {
        let h = try FakeHome()
        let agents = try h.dir("Library/LaunchAgents")
        let live: NSDictionary = ["Label": "com.gone.updater", "ProgramArguments": ["/bin/ls"]]
        live.write(to: agents.appendingPathComponent("com.gone.updater.plist"), atomically: true)
        let dead: NSDictionary = ["Label": "com.gone2.updater", "Program": "/Applications/Gone.app/Contents/MacOS/upd"]
        dead.write(to: agents.appendingPathComponent("com.gone2.updater.plist"), atomically: true)
        let items = finder(h, installed: []).find()
        #expect(items.map(\.url.lastPathComponent) == ["com.gone2.updater.plist"])
        #expect(items.first?.preselected == false) // background tasks are never pre-ticked
    }

    @Test func bundleIDParsing() {
        #expect(OrphanFinder.bundleID(from: "group.com.foo.bar", root: "Group Containers") == "com.foo.bar")
        #expect(OrphanFinder.bundleID(from: "Foo Bar", root: "Application Support") == nil)
        #expect(OrphanFinder.bundleID(from: "com.apple.Safari", root: "Caches") == nil)
        #expect(OrphanFinder.bundleID(from: "UBF8T346G9.com.apple.notes", root: "Group Containers") == nil)
        #expect(OrphanFinder.vendor(of: "io.github.someone.tool") == "io.github.someone")
    }
}
