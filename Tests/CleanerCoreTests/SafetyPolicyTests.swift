import Foundation
import Testing
@testable import CleanerCore

/// Builds a throwaway fake home folder so tests never point at the real one.
final class FakeHome {
    let url: URL
    let fm = FileManager.default

    init() throws {
        url = fm.temporaryDirectory.appendingPathComponent("compclean-\(UUID().uuidString)/home")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? fm.removeItem(at: url.deletingLastPathComponent()) }

    @discardableResult
    func dir(_ rel: String) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    @discardableResult
    func file(_ rel: String, bytes: Int = 16) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: u)
        return u
    }

    var policy: SafetyPolicy { SafetyPolicy(home: url, isAppleSigned: { _ in false }) }
}

@Suite struct MacOSProtectionTests {
    let realPolicy = SafetyPolicy()

    @Test(arguments: [
        "/System", "/System/Library/CoreServices", "/System/Applications/Calculator.app",
        "/usr/bin", "/bin/ls", "/sbin", "/private/var", "/etc/hosts", "/var/log",
        "/Library/Apple", "/Library/Logs/DiagnosticReports", "/Library/Extensions",
        "/Library/Frameworks", "/Applications/Utilities/Terminal.app",
        "/Applications/Safari.app", "/", "/Library", "/Applications",
    ])
    func systemPathsRefusedForEveryPurpose(_ path: String) {
        let url = URL(fileURLWithPath: path)
        for purpose in [Purpose.clean, .reviewDownloads, .uninstall] {
            #expect(!realPolicy.canTrash(url, for: purpose), "\(path) allowed for \(purpose)")
        }
    }

    @Test func realHomeAndLibraryRefused() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for rel in ["", "Library", "Library/Caches", "Library/Logs", "Library/Application Support",
                    "Library/Preferences", "Library/Containers", "Library/Keychains", "Library/Mail"] {
            let url = rel.isEmpty ? home : home.appendingPathComponent(rel)
            for purpose in [Purpose.clean, .reviewDownloads, .uninstall] {
                #expect(!realPolicy.canTrash(url, for: purpose), "~/\(rel) allowed for \(purpose)")
            }
        }
    }

    @Test func appleCachesAndPlainAppleNamesRefused() throws {
        let h = try FakeHome()
        for name in ["com.apple.Safari", "com.apple.Music", "CloudKit", "GeoServices",
                     "SiriEntityCache", "group.com.apple.notes", "AppleSpell"] {
            let u = try h.dir("Library/Caches/\(name)")
            #expect(!h.policy.canTrash(u, for: .clean), "\(name) allowed")
        }
        let prefs = try h.file("Library/Preferences/com.apple.finder.plist")
        #expect(!h.policy.canTrash(prefs, for: .uninstall))
    }

    @Test func symlinkIntoSystemRefused() throws {
        let h = try FakeHome()
        let caches = try h.dir("Library/Caches")
        let link = caches.appendingPathComponent("com.evil.app")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/usr")
        #expect(!h.policy.canTrash(link, for: .clean))
        #expect(!h.policy.canTrash(link.appendingPathComponent("bin"), for: .clean))
        #expect(!h.policy.canTrash(link, for: .uninstall))
    }

    @Test func diagnosticReportsRefused() throws {
        let h = try FakeHome()
        let u = try h.file("Library/Logs/DiagnosticReports/foo.ips")
        #expect(!h.policy.canTrash(u, for: .clean))
    }

    @Test func appleAppsRefusedForUninstall() throws {
        let h = try FakeHome()
        let app = try h.dir("Applications/Fake.app")
        let apple = SafetyPolicy(home: h.url, isAppleSigned: { _ in true })
        #expect(!apple.canTrash(app, for: .uninstall))
        #expect(h.policy.canTrash(app, for: .uninstall))
    }
}

@Suite struct LoginDataProtectionTests {
    @Test(arguments: [
        "Library/Cookies/Cookies.binarycookies",
        "Library/HTTPStorages/com.foo.bar",
        "Library/WebKit/com.foo.bar",
        "Library/Application Support/Google/Chrome/Default/Cookies",
        "Library/Application Support/Google/Chrome/Default/Network",
        "Library/Application Support/Google/Chrome/Default/Login Data",
        "Library/Application Support/Google/Chrome/Default/Local Storage",
        "Library/Application Support/Google/Chrome/Default/IndexedDB",
        "Library/Application Support/Google/Chrome/Local State",
        "Library/Application Support/Firefox/Profiles/x.default/cookies.sqlite",
        "Library/Containers/com.foo.bar/Data",
        "Library/Keychains/login.keychain-db",
    ])
    func loginDataRefusedForCleaning(_ rel: String) throws {
        let h = try FakeHome()
        let u = try h.file(rel)
        #expect(!h.policy.canTrash(u, for: .clean), "\(rel) allowed")
    }

    @Test func cacheFolderHidingCookiesRefused() throws {
        let h = try FakeHome()
        try h.file("Library/Caches/com.foo.bar/web/Cookies")
        #expect(!h.policy.canTrash(h.url.appendingPathComponent("Library/Caches/com.foo.bar"), for: .clean))
    }
}

@Suite struct AllowedTests {
    @Test(arguments: [
        "Library/Caches/com.spotify.client",
        "Library/Caches/Homebrew",
        "Library/Caches/Firefox/Profiles/x.default/cache2",
        "Library/Application Support/Google/Chrome/Default/Cache",
        "Library/Application Support/Google/Chrome/Profile 1/Code Cache",
        "Library/Application Support/Google/Chrome/Default/Service Worker/CacheStorage",
        "Library/Application Support/BraveSoftware/Brave-Browser/Default/GPUCache",
        "Library/Application Support/Google/Chrome/GrShaderCache",
        "Library/Logs/com.foo.bar/old.log",
        "Library/Developer/Xcode/DerivedData/MyApp-abc",
        ".npm/_cacache",
    ])
    func cleanableCachesAllowed(_ rel: String) throws {
        let h = try FakeHome()
        let u = try h.dir(rel)
        #expect(h.policy.canTrash(u, for: .clean), "\(rel) refused: \(h.policy.check(u, for: .clean))")
    }

    @Test func uninstallLeftoversAllowed() throws {
        let h = try FakeHome()
        for rel in ["Library/Application Support/Foo", "Library/Preferences/com.foo.bar.plist",
                    "Library/Containers/com.foo.bar", "Library/Cookies/com.foo.bar.binarycookies",
                    "Library/Saved Application State/com.foo.bar.savedState"] {
            let u = try h.file(rel)
            #expect(h.policy.canTrash(u, for: .uninstall), "\(rel) refused")
        }
    }

    @Test func downloadsOnlyTopLevel() throws {
        let h = try FakeHome()
        let top = try h.file("Downloads/old.zip")
        let nested = try h.file("Downloads/folder/inner.zip")
        #expect(h.policy.canTrash(top, for: .reviewDownloads))
        #expect(!h.policy.canTrash(nested, for: .reviewDownloads))
        #expect(!h.policy.canTrash(top, for: .clean))
    }
}
