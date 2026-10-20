import Foundation

/// Finds cleanable items. Everything it returns already passed `SafetyPolicy`;
/// `Trasher` checks again before moving anything.
public struct Scanner: Sendable {
    public let policy: SafetyPolicy
    public let home: URL
    /// Bundle ids of apps running now. Their caches are skipped.
    public let runningBundleIDs: Set<String>
    public let now: Date

    public init(policy: SafetyPolicy, runningBundleIDs: Set<String> = [], now: Date = Date()) {
        self.policy = policy
        self.home = URL(fileURLWithPath: policy.home)
        self.runningBundleIDs = Set(runningBundleIDs.map { $0.lowercased() })
        self.now = now
    }

    static let logAge: TimeInterval = 7 * 86_400
    static let downloadAge: TimeInterval = 90 * 86_400

    /// Plain-named cache folders handled by the developer category instead.
    static let devCacheNames: Set<String> = ["homebrew", "yarn", "pip", "pypoetry", "node-gyp", "pnpm", "go-build"]

    /// Owners of plain-named folders, so caches of running apps get skipped.
    static let ownerBundleIDs: [String: [String]] = [
        "google": ["com.google.chrome"],
        "firefox": ["org.mozilla.firefox"],
        "mozilla": ["org.mozilla.firefox"],
        "bravesoftware": ["com.brave.browser"],
        "microsoft edge": ["com.microsoft.edgemac"],
        "arc": ["company.thebrowser.browser"],
        "vivaldi": ["com.vivaldi.vivaldi"],
        "steam": ["com.valvesoftware.steam"],
        "spotify": ["com.spotify.client"],
        "slack": ["com.tinyspeck.slackmacgap"],
        "discord": ["com.hnc.discord"],
        "zoom.us": ["us.zoom.xos"],
        "chatgpthelper": ["com.openai.chat"],
    ]

    static let browserBundleIDs: [String: String] = [
        "Google/Chrome": "com.google.chrome",
        "BraveSoftware/Brave-Browser": "com.brave.browser",
        "Microsoft Edge": "com.microsoft.edgemac",
        "Arc/User Data": "company.thebrowser.browser",
        "Vivaldi": "com.vivaldi.vivaldi",
    ]

    public func scan(_ categories: Set<CleanCategory>) -> [Finding] {
        var out: [Finding] = []
        for category in CleanCategory.allCases where categories.contains(category) {
            out += scan(category)
        }
        return out.sorted { $0.size > $1.size }
    }

    public func scan(_ category: CleanCategory) -> [Finding] {
        let candidates: [URL]
        switch category {
        case .userCaches: candidates = userCaches()
        case .browserCaches: candidates = browserCaches()
        case .oldLogs: candidates = oldLogs()
        case .devCaches: candidates = devCaches()
        case .oldDownloads: candidates = oldDownloads()
        }
        return candidates.compactMap { url in
            guard policy.canTrash(url, for: category.purpose) else { return nil }
            let size = FileSize.allocated(url)
            return size > 0 ? Finding(url: url, size: size, category: category) : nil
        }
    }

    // MARK: - Categories

    private func lib(_ rel: String) -> URL { home.appendingPathComponent("Library/\(rel)") }

    private func userCaches() -> [URL] {
        FileSize.children(lib("Caches")).filter { url in
            let name = url.lastPathComponent.lowercased()
            return !Self.devCacheNames.contains(name) && !isOwnedByRunningApp(name)
        }
    }

    private func browserCaches() -> [URL] {
        var out: [URL] = []
        let support = lib("Application Support")
        for (root, bundleID) in Self.browserBundleIDs where !runningBundleIDs.contains(bundleID) {
            let rootURL = support.appendingPathComponent(root)
            guard FileSize.isDirectory(rootURL) else { continue }
            let levels = [rootURL] + FileSize.children(rootURL).filter(FileSize.isDirectory)
            for base in levels {
                for part in SafetyPolicy.browserCacheParts {
                    let u = base.appendingPathComponent(part.joined(separator: "/"))
                    if FileSize.isDirectory(u) { out.append(u) }
                }
            }
        }
        return out
    }

    private func oldLogs() -> [URL] {
        var out: [URL] = []
        for owner in FileSize.children(lib("Logs")) where FileSize.isDirectory(owner) {
            guard !isOwnedByRunningApp(owner.lastPathComponent.lowercased()) else { continue }
            guard let walker = FileManager.default.enumerator(
                at: owner, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
            ) else { continue }
            while let file = walker.nextObject() as? URL {
                let v = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                guard v?.isRegularFile == true, let date = v?.contentModificationDate else { continue }
                if now.timeIntervalSince(date) > Self.logAge { out.append(file) }
            }
        }
        return out
    }

    private func devCaches() -> [URL] {
        var out: [URL] = []
        for name in ["Homebrew", "Yarn", "pip", "pypoetry", "node-gyp", "pnpm", "go-build"] {
            let u = lib("Caches/\(name)")
            if FileSize.isDirectory(u) { out.append(u) }
        }
        for rel in [".npm/_cacache", ".cache/uv", ".cache/pip"] {
            let u = home.appendingPathComponent(rel)
            if FileSize.isDirectory(u) { out.append(u) }
        }
        out += FileSize.children(lib("Developer/Xcode/DerivedData")).filter(FileSize.isDirectory)
        return out
    }

    private func oldDownloads() -> [URL] {
        let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .contentAccessDateKey, .contentModificationDateKey]
        return FileSize.children(home.appendingPathComponent("Downloads")).filter { url in
            guard !url.lastPathComponent.hasPrefix("."), let v = try? url.resourceValues(forKeys: keys) else {
                return false
            }
            let dates = [v.addedToDirectoryDate, v.contentAccessDate, v.contentModificationDate].compactMap { $0 }
            guard let newest = dates.max() else { return false }
            return now.timeIntervalSince(newest) > Self.downloadAge
        }
    }

    private func isOwnedByRunningApp(_ lowerName: String) -> Bool {
        if runningBundleIDs.contains(where: { lowerName == $0 || lowerName.hasPrefix($0 + ".") }) {
            return true
        }
        return Self.ownerBundleIDs[lowerName]?.contains(where: runningBundleIDs.contains) ?? false
    }
}
