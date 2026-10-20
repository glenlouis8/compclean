import AppKit
import Foundation

/// Turns paths into plain language: which app owns it, what it is, and why it's safe to remove.
public struct ItemExplainer: Sendable {
    public let home: String

    public init(home: String = SafetyPolicy().home) {
        self.home = home
    }

    /// Plain-named folders and the app they belong to.
    static let knownOwners: [String: (name: String, bundleID: String?)] = [
        "bravesoftware": ("Brave Browser", "com.brave.Browser"),
        "google": ("Google Chrome", "com.google.Chrome"),
        "firefox": ("Firefox", "org.mozilla.firefox"),
        "mozilla": ("Firefox", "org.mozilla.firefox"),
        "microsoft edge": ("Microsoft Edge", "com.microsoft.edgemac"),
        "arc": ("Arc", "company.thebrowser.Browser"),
        "vivaldi": ("Vivaldi", "com.vivaldi.Vivaldi"),
        "steam": ("Steam", "com.valvesoftware.steam"),
        "spotify": ("Spotify", "com.spotify.client"),
        "slack": ("Slack", "com.tinyspeck.slackmacgap"),
        "discord": ("Discord", "com.hnc.Discord"),
        "zoom.us": ("Zoom", "us.zoom.xos"),
        "jetbrains": ("JetBrains IDEs", nil),
        "homebrew": ("Homebrew", nil),
        "yarn": ("Yarn", nil),
        "pip": ("pip (Python)", nil),
        "pypoetry": ("Poetry (Python)", nil),
        "node-gyp": ("node-gyp", nil),
        "pnpm": ("pnpm", nil),
        "go-build": ("Go", nil),
        "claude-cli-nodejs": ("Claude Code", nil),
        "chatgpthelper": ("ChatGPT", "com.openai.chat"),
        "sentrycrash": ("Crash reporter (Sentry)", nil),
        "artcraft launcher": ("ArtCraft Launcher", nil),
    ]

    static let browserNames: [String: String] = [
        "Google/Chrome": "Google Chrome", "BraveSoftware/Brave-Browser": "Brave Browser",
        "Microsoft Edge": "Microsoft Edge", "Arc/User Data": "Arc", "Vivaldi": "Vivaldi",
    ]

    // MARK: - Owners

    public struct Owner: Sendable {
        public let name: String
        public let bundleID: String?
        public let appPath: String?
    }

    /// Finds the app behind a folder or file name like "com.spotify.client.plist" or "BraveSoftware".
    public func owner(forName rawName: String) -> Owner? {
        var name = rawName
        for suffix in [".plist", ".savedState", ".binarycookies", ".log"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        if let known = Self.knownOwners[name.lowercased()] {
            let path = known.bundleID.flatMap(Self.appPath(forBundleID:))
            return Owner(name: path.flatMap(Self.displayName) ?? known.name, bundleID: known.bundleID, appPath: path)
        }
        var parts = name.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return nil }
        // Try the full id, then drop trailing parts: com.foo.app.helper -> com.foo.app.
        while parts.count >= 3 {
            let id = parts.joined(separator: ".")
            if let path = Self.appPath(forBundleID: id) {
                return Owner(name: Self.displayName(path) ?? id, bundleID: id, appPath: path)
            }
            parts.removeLast()
        }
        return nil
    }

    static func appPath(forBundleID id: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
    }

    static func displayName(_ appPath: String) -> String? {
        let info = Bundle(path: appPath)?.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
            ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    }

    /// Readable name for a reverse-DNS id with no installed app.
    /// "com.spotify.client" -> "Spotify", "com.macpaw.CleanMyMac-mas" -> "CleanMyMac".
    public static func guessName(fromBundleID id: String) -> String {
        let parts = id.split(separator: ".").map(String.init)
        let skip: Set<String> = ["co", "client", "mac", "macos", "osx", "desktop", "helper", "app", "group", "shared", "main"]
        // Drop the country/org part and generic words: what's left is vendor, then product names.
        let meaningful = parts.dropFirst().filter { !skip.contains($0.lowercased()) }
        guard let vendorRaw = meaningful.first else { return parts.last ?? id }
        let vendor = capitalized(vendorRaw)
        // A product name usually keeps its capitals (CleanMyMac, AdGuard); fall back to the vendor.
        guard var product = meaningful.dropFirst().first(where: { $0 != $0.lowercased() }) else { return vendor }
        for suffix in ["-mas", "-setapp", "-paddle", "-mac", "-macos", "-osx"] where product.lowercased().hasSuffix(suffix) {
            product = String(product.dropLast(suffix.count))
        }
        let p = product.lowercased(), v = vendorRaw.lowercased()
        return p.contains(v) || v.contains(p) ? product : "\(product) by \(vendor)"
    }

    private static func capitalized(_ s: String) -> String {
        s == s.lowercased() ? s.prefix(1).uppercased() + s.dropFirst() : s
    }

    // MARK: - Cleaner findings

    public func explain(_ finding: Finding) -> Explanation {
        let rel = relativeParts(finding.url)
        let lastUsed = Self.lastUsed(finding.url)
        switch finding.category {
        case .userCaches:
            let o = owner(forName: finding.url.lastPathComponent)
            let who = o?.name ?? finding.url.lastPathComponent
            return Explanation(
                title: "\(who) · cache", ownerName: o?.name, ownerAppPath: o?.appPath, safety: .rebuildsItself,
                reason: "Temporary files \(o?.name ?? "the app") keeps to load faster. It rebuilds them automatically when needed.",
                lastUsed: lastUsed)
        case .browserCaches:
            let browser = Self.browserNames.first { finding.url.path.contains("/\($0.key)/") }?.value ?? "Browser"
            let path = Self.browserNames.first { finding.url.path.contains("/\($0.key)/") }
                .flatMap { k in ItemExplainer.knownOwners.values.first { $0.name == k.value }?.bundleID }
                .flatMap(Self.appPath(forBundleID:))
            return Explanation(
                title: "\(browser) · \(finding.url.lastPathComponent)", ownerName: browser, ownerAppPath: path,
                safety: .rebuildsItself,
                reason: "Saved copies of web pages and their code. \(browser) downloads them again as you browse. You stay signed in, and history and bookmarks are untouched.",
                lastUsed: lastUsed)
        case .oldLogs:
            let folder = rel.count > 2 ? rel[2] : finding.url.deletingLastPathComponent().lastPathComponent
            let o = owner(forName: folder)
            return Explanation(
                title: "\(finding.url.lastPathComponent) · \(o?.name ?? folder) log", ownerName: o?.name,
                ownerAppPath: o?.appPath, safety: .rebuildsItself,
                reason: "A record of what the app did, only useful for troubleshooting. It's more than 7 days old.",
                lastUsed: lastUsed)
        case .devCaches:
            return explainDevCache(finding, rel: rel, lastUsed: lastUsed)
        case .oldDownloads:
            return Explanation(
                title: finding.url.lastPathComponent, safety: .yourFile,
                reason: "In your Downloads and not opened for over 90 days. This is your own file, so check it before removing.",
                lastUsed: lastUsed)
        }
    }

    private func explainDevCache(_ f: Finding, rel: [String], lastUsed: Date?) -> Explanation {
        let name = f.url.lastPathComponent
        let (title, reason): (String, String)
        switch name.lowercased() {
        case "homebrew": (title, reason) = ("Homebrew downloads", "Installer files Homebrew already used. It downloads them again if it ever needs them.")
        case "_cacache": (title, reason) = ("npm download cache", "Copies of packages npm downloaded before. Projects keep working; npm re-downloads on the next install.")
        case "yarn", "pnpm": (title, reason) = ("\(name.capitalized) download cache", "Copies of downloaded JavaScript packages. Re-downloaded when needed.")
        case "pip", "uv", "pypoetry": (title, reason) = ("Python package cache (\(name))", "Copies of downloaded Python packages. Re-downloaded when needed.")
        case "node-gyp": (title, reason) = ("node-gyp headers", "Build headers for native Node modules. Re-downloaded when needed.")
        case "go-build": (title, reason) = ("Go build cache", "Compiled Go files. Go rebuilds them when you build again.")
        default:
            if rel.contains("DerivedData") {
                let project = name.split(separator: "-").dropLast().joined(separator: "-")
                (title, reason) = ("Xcode build files · \(project.isEmpty ? name : project)", "Intermediate files Xcode creates while building. It recreates them on the next build.")
            } else {
                (title, reason) = (name, "A developer tool cache that's recreated when needed.")
            }
        }
        return Explanation(title: title, ownerName: nil, ownerAppPath: nil, safety: .rebuildsItself, reason: reason, lastUsed: lastUsed)
    }

    // MARK: - Helpers

    func relativeParts(_ url: URL) -> [String] {
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(home + "/") else { return p.split(separator: "/").map(String.init) }
        return p.dropFirst(home.count + 1).split(separator: "/").map(String.init)
    }

    /// Best guess of when the item was last used: access date for files, newest change for folders.
    public static func lastUsed(_ url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .contentModificationDateKey, .isDirectoryKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return nil }
        if v.isDirectory == true { return v.contentModificationDate }
        return [v.contentAccessDate, v.contentModificationDate].compactMap { $0 }.max()
    }
}

extension Finding {
    public func reviewItem(explainer: ItemExplainer) -> ReviewItem {
        ReviewItem(url: url, size: size, explanation: explainer.explain(self), group: category.title,
                   preselected: category.autoSafe, purpose: category.purpose)
    }
}
