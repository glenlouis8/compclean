import Foundation
import Testing
@testable import CleanerCore

@Suite struct AppUsageTests {
    @Test func filtersAndSorts() {
        func app(_ n: String) -> AppInfo {
            AppInfo(url: URL(fileURLWithPath: "/Applications/\(n).app"), name: n, bundleID: "com.x.\(n)",
                    version: nil, teamID: nil, isApple: false)
        }
        let now = Date()
        let dates: [String: Date] = ["Old": now.addingTimeInterval(-400 * 86_400),
                                     "Older": now.addingTimeInterval(-900 * 86_400),
                                     "Fresh": now.addingTimeInterval(-3 * 86_400)]
        let result = AppUsage.unused([app("Old"), app("Older"), app("Fresh"), app("Never")], months: 6, now: now) {
            dates[$0.deletingPathExtension().lastPathComponent]
        }
        #expect(result.map(\.app.name) == ["Older", "Old", "Never"])
    }
}

@Suite struct DevJunkFinderTests {
    func age(_ url: URL, days: Double) throws {
        let date = Date().addingTimeInterval(-days * 86_400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test func flagsOnlyStaleProjects() throws {
        let h = try FakeHome()
        let oldPkg = try h.file("Coding/old-site/package.json")
        try age(oldPkg, days: 120)
        try h.file("Coding/old-site/node_modules/react/index.js", bytes: 4096)

        let newPkg = try h.file("Coding/fresh/package.json")
        try age(newPkg, days: 2)
        try h.file("Coding/fresh/node_modules/react/index.js", bytes: 4096)

        let cargo = try h.file("Coding/rusty/Cargo.toml")
        try age(cargo, days: 60)
        try h.file("Coding/rusty/target/debug/app", bytes: 4096)

        let cfg = try h.file("Coding/py/.venv/pyvenv.cfg")
        try h.file("Coding/py/.venv/lib/x.py", bytes: 4096)
        let main = try h.file("Coding/py/main.py")
        try age(main, days: 90)
        try age(cfg, days: 90)

        try h.file("Coding/movies/target/clip.mov", bytes: 4096) // no Cargo.toml: not junk

        let items = DevJunkFinder(policy: h.policy, roots: [h.url.appendingPathComponent("Coding")]).find()
        let titles = Set(items.map(\.explanation.title))
        #expect(titles == ["old-site · node_modules", "rusty · target", "py · .venv"], "got \(titles)")
        #expect(items.first { $0.explanation.title == "py · .venv" }?.preselected == false)
        #expect(items.allSatisfy { $0.purpose == .devProjects })
    }

    @Test func playwrightBrowsersOfferedPerVersion() throws {
        let h = try FakeHome()
        try h.file("Library/Caches/ms-playwright/chromium-1140/chrome-mac/Chromium.app/x", bytes: 4096)
        try h.file("Library/Caches/ms-playwright/webkit-2104/pw_run.sh", bytes: 4096)
        let items = DevJunkFinder(policy: h.policy, roots: []).find()
        #expect(Set(items.map(\.url.lastPathComponent)) == ["chromium-1140", "webkit-2104"])
        #expect(items.allSatisfy { $0.group == "Playwright test browsers" && $0.explanation.safety == .reviewFirst })
        // The folder itself is never offered, and the cleaner never touches it.
        #expect(!h.policy.canTrash(h.url.appendingPathComponent("Library/Caches/ms-playwright"), for: .devProjects))
        #expect(!h.policy.canTrash(h.url.appendingPathComponent("Library/Caches/ms-playwright"), for: .clean))
    }

    @Test func junkFilesDontCountAsActivity() throws {
        let h = try FakeHome()
        let pkg = try h.file("Coding/app/package.json")
        try age(pkg, days: 100)
        try h.file("Coding/app/node_modules/x/new.js", bytes: 4096) // fresh, but inside junk
        let items = DevJunkFinder(policy: h.policy, roots: [h.url.appendingPathComponent("Coding")]).find()
        #expect(items.count == 1)
    }
}
