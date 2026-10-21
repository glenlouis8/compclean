#if DEBUG
import CleanerCore
import SwiftUI

/// Made-up scan results so Xcode can render every screen without touching the real disk.
@MainActor
enum PreviewData {
    static let home = SafetyPolicy().home
    static func url(_ rel: String) -> URL { URL(fileURLWithPath: home + "/" + rel) }

    static let findings: [Finding] = [
        Finding(url: url("Library/Caches/BraveSoftware"), size: 1_302_000_000, category: .userCaches),
        Finding(url: url("Library/Caches/Steam"), size: 218_000_000, category: .userCaches),
        Finding(url: url("Library/Caches/com.spotify.client"), size: 92_400_000, category: .userCaches),
        Finding(url: url("Library/Caches/com.raycast.macos"), size: 156_000, category: .userCaches),
        Finding(url: url("Library/Application Support/Google/Chrome/Default/Cache"), size: 412_000_000, category: .browserCaches),
        Finding(url: url("Library/Application Support/Google/Chrome/Default/Code Cache"), size: 88_000_000, category: .browserCaches),
        Finding(url: url("Library/Logs/com.spotify.client/spotify-2026-08.log"), size: 2_100_000, category: .oldLogs),
        Finding(url: url(".npm/_cacache"), size: 1_789_000_000, category: .devCaches),
        Finding(url: url("Library/Caches/Homebrew"), size: 65_600_000, category: .devCaches),
        Finding(url: url("Library/Developer/Xcode/DerivedData/CompClean-abcdef"), size: 512_000_000, category: .devCaches),
    ]

    static let apps: [AppInfo] = [
        ("Obsidian", "md.obsidian", "1.12.7"), ("Brave Browser", "com.brave.Browser", "155.1.97"),
        ("WhatsApp", "net.whatsapp.WhatsApp", "26.40.77"), ("NordVPN", "com.nordvpn.macos", "10.8.1"),
        ("zoom.us", "us.zoom.xos", "7.1.9"), ("Warp", "dev.warp.Warp-Stable", "0.2026.10"),
        ("OBS", "com.obsproject.obs-studio", "32.1.2"),
    ].map { name, id, version in
        AppInfo(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: id,
                version: version, teamID: nil, isApple: false)
    }

    /// A model that looks like a finished Cleaner scan.
    static func model(scanned: Bool = true) -> AppModel {
        let m = AppModel()
        m.diskTotal = 494_380_000_000
        m.diskFree = 326_420_000_000
        m.quickEstimate = 1_612_000_000
        m.apps = apps
        for (i, app) in apps.enumerated() { m.appSizes[app.id] = Int64(900_000_000 - i * 110_000_000) }
        guard scanned else { return m }
        m.findings = findings
        m.explanations = Dictionary(uniqueKeysWithValues: findings.map { ($0.id, m.explainer.explain($0)) })
        m.selected = Set(findings.map(\.id))
        m.scannedCategories = [.userCaches, .browserCaches, .oldLogs, .devCaches]
        m.hasScanned = true
        m.scanSummary = "4.48 GB can be cleaned, mostly Brave's cache and old npm downloads. Nothing personal like documents, cookies or logins is included."
        return m
    }

    /// The uninstaller with an app picked and its leftovers listed.
    static func uninstallModel() -> AppModel {
        let m = model(scanned: false)
        let app = apps[0]
        m.chosenApp = app
        m.leftovers = [
            Leftover(url: app.url, size: 505_300_000, match: .app, needsAdmin: false),
            Leftover(url: url("Library/Application Support/obsidian"), size: 212_000_000, match: .appName, needsAdmin: false),
            Leftover(url: url("Library/Caches/md.obsidian"), size: 48_000_000, match: .bundleID, needsAdmin: false),
            Leftover(url: url("Library/Preferences/md.obsidian.plist"), size: 4_000, match: .bundleID, needsAdmin: false),
            Leftover(url: url("Library/Saved Application State/md.obsidian.savedState"), size: 12_000, match: .bundleID, needsAdmin: false),
            Leftover(url: URL(fileURLWithPath: "/Library/LaunchAgents/md.obsidian.updater.plist"), size: 4_000, match: .company, needsAdmin: true),
        ]
        m.leftoverSelection = Set(m.leftovers.filter(\.match.preselected).map(\.id))
        return m
    }

    /// Leftovers from deleted apps, as the Leftovers screen lists them.
    static func leftoversModel() -> AppModel {
        let m = model(scanned: false)
        let store = m.leftoversStore
        func item(_ rel: String, _ size: Int64, _ app: String, _ label: String, days: Double) -> ReviewItem {
            ReviewItem(url: url(rel), size: size,
                       explanation: Explanation(title: "\(app) · \(label)", safety: .leftover,
                                                reason: "\(app) isn't installed anymore, but it left this behind. No installed app uses it.",
                                                lastUsed: Date().addingTimeInterval(-days * 86_400)),
                       group: "\(app) (not installed)", preselected: true, purpose: .uninstall)
        }
        store.items = [
            item("Library/Application Support/com.spotify.client", 182_000_000, "Spotify", "app data", days: 400),
            item("Library/Caches/com.spotify.client", 41_000_000, "Spotify", "cache", days: 400),
            item("Library/Preferences/com.spotify.client.plist", 8_000, "Spotify", "settings", days: 400),
            item("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram", 96_000_000, "Telegram", "shared data", days: 210),
            item("Library/Containers/com.adguard.safari.AdGuard", 33_000, "AdGuard", "sandbox data", days: 500),
        ]
        store.selection = Set(store.items.map(\.id))
        store.hasScanned = true
        return m
    }

    /// A small home-folder map.
    static func diskMapModel() -> AppModel {
        let m = model(scanned: false)
        func node(_ name: String, _ gb: Double, _ kids: [DiskNode] = []) -> DiskNode {
            DiskNode(path: home + "/" + name, name: name, size: Int64(gb * 1_000_000_000), isFolder: true, children: kids)
        }
        let root = DiskNode(path: home, name: "home", size: 51_880_000_000, isFolder: true, children: [
            node("Library", 30.4, [node("Library/Application Support", 29.0), node("Library/Caches", 0.8)]),
            node("Coding", 12.1, [node("Coding/remedi", 2.0), node("Coding/audit-ai", 1.6), node("Coding/voltcast", 1.5)]),
            node(".cache", 2.0), node(".local", 1.7), node(".claude", 1.0), node(".vscode", 0.99),
            node("Downloads", 0.8), node("Documents", 0.6), node("Applications", 0.5), node("Desktop", 0.2),
        ])
        m.diskMap.root = root
        return m
    }
}

extension View {
    /// Everything a screen expects from its surroundings, using preview data.
    func previewEnvironment(_ model: AppModel = PreviewData.model(), width: CGFloat = 700, height: CGFloat = 560) -> some View {
        environmentObject(model)
            .environmentObject(model.history)
            .environmentObject(model.ai)
            .frame(width: width, height: height)
    }
}
#endif
