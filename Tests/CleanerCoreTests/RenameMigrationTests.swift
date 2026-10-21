import Foundation
import Testing
@testable import CleanerCore

@Suite("Rename from CompClean")
struct RenameMigrationTests {
    @Test("History, log and settings move over once, and nothing is overwritten")
    func movesOnce() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("suds-rename-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let oldHistory = home.appendingPathComponent("Library/Application Support/CompClean/history.json")
        let oldLog = home.appendingPathComponent("Library/Logs/CompClean/actions.log")
        for file in [oldHistory, oldLog] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("old".utf8).write(to: file)
        }
        let newID = "test.suds.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.setPersistentDomain(["seenWelcome": true], forName: RenameMigration.oldBundleID + ".test")
        defer {
            defaults.removePersistentDomain(forName: newID)
            defaults.removePersistentDomain(forName: RenameMigration.oldBundleID + ".test")
        }

        RenameMigration.run(home: home.path, bundleID: newID, defaults: defaults,
                            oldBundleID: RenameMigration.oldBundleID + ".test")

        let newHistory = home.appendingPathComponent("Library/Application Support/Suds/history.json")
        #expect(try Data(contentsOf: newHistory) == Data("old".utf8))
        #expect(fm.fileExists(atPath: home.appendingPathComponent("Library/Logs/Suds/actions.log").path))
        #expect(!fm.fileExists(atPath: oldHistory.path))
        #expect(defaults.persistentDomain(forName: newID)?["seenWelcome"] as? Bool == true)

        // A second run with fresh old data leaves the new files alone.
        try fm.createDirectory(at: oldHistory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: oldHistory)
        RenameMigration.run(home: home.path, bundleID: newID, defaults: defaults,
                            oldBundleID: RenameMigration.oldBundleID + ".test")
        #expect(try Data(contentsOf: newHistory) == Data("old".utf8))
    }
}
