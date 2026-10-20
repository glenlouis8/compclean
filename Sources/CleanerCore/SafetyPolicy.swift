import Foundation

/// Why a path is being removed. Each purpose has its own allowlist.
public enum Purpose: String, Sendable, Codable {
    case clean            // caches, logs, dev caches
    case reviewDownloads  // old items in ~/Downloads, manual only
    case uninstall        // an app bundle and its leftovers
    case devProjects      // build/dependency folders inside code projects
    case userFiles        // big or duplicate files the user reviews one by one
}

public enum Verdict: Equatable, Sendable {
    case allowed
    case refused(String)

    public var isAllowed: Bool { self == .allowed }
}

/// The single gate every removal goes through. Allowlist based: anything not
/// explicitly allowed is refused. macOS and Apple items are never allowed.
public struct SafetyPolicy: Sendable {
    public let home: String
    private let homeIsSane: Bool
    private let isAppleSigned: @Sendable (URL) -> Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        isAppleSigned: @escaping @Sendable (URL) -> Bool = { CodeSignature.isAppleSigned($0) }
    ) {
        let resolved = SafetyPolicy.realPath(home.path) ?? home.standardizedFileURL.path
        self.home = resolved
        self.isAppleSigned = isAppleSigned
        let depth = resolved.split(separator: "/").count
        self.homeIsSane = depth >= 2
            && !SafetyPolicy.systemRoots.contains(resolved)
            && !SafetyPolicy.systemRoots.contains { $0.hasPrefix(resolved + "/") }
    }

    // MARK: - Rule tables

    /// Never touched, no matter what any other rule says.
    static let systemRoots = [
        "/System", "/usr", "/bin", "/sbin", "/private", "/etc", "/var", "/tmp",
        "/cores", "/dev", "/opt", "/Volumes", "/Network",
        "/Library/Apple", "/Library/Logs", "/Library/Updates", "/Library/Extensions",
        "/Library/Frameworks", "/Library/Keychains", "/Library/Security",
        "/Library/SystemExtensions", "/Library/Filesystems", "/Library/CoreMediaIO",
        "/Applications/Utilities",
    ]

    /// Names that hold logins, cookies or personal data. Refused for clean purposes,
    /// and a directory containing any of them is refused too.
    static let protectedNames: Set<String> = [
        "login data", "login data-journal", "login data for account", "local storage",
        "session storage", "indexeddb", "web data", "web data-journal", "local state",
        "keychains", "key4.db", "logins.json", "cert9.db", "places.sqlite",
        "databases", "sync data", "accounts",
        // Browsing history and bookmarks.
        "history", "history-journal", "archived history", "bookmarks", "bookmarks.bak",
        "favicons", "favicons-journal", "top sites", "top sites-journal", "shortcuts",
        "visited links", "preferences", "secure preferences", "favicons.sqlite",
    ]

    /// macOS parts that use old, non-"com.apple" names (printing, Shortcuts, WebKit, OpenSSH…).
    static let appleLegacyPrefixes = ["is.workflow.", "org.cups.", "org.webkit.", "com.openssh.", "org.openldap.",
                                      "org.postfix.", "org.ntp.", "org.isc.", "org.x.x11", "org.xquartz."]

    /// Bundle-style folders that look like files in Finder but hold a whole library.
    static let packageExtensions: Set<String> = [
        "photoslibrary", "musiclibrary", "tvlibrary", "app", "logicx", "fcpbundle",
        "imovielibrary", "photolibrary", "aplibrary", "band", "xcarchive",
    ]

    /// Junk folder name -> marker that proves it belongs to a code project.
    /// "parent:" means the marker sits next to the folder, "self:" means inside it.
    static let devJunk: [String: String] = [
        "node_modules": "parent:package.json",
        ".venv": "self:pyvenv.cfg",
        "venv": "self:pyvenv.cfg",
        "target": "parent:Cargo.toml",
        ".build": "parent:Package.swift",
        ".terraform": "parent:.terraform.lock.hcl",
    ]

    /// Xcode folders whose children are safe to review and remove.
    static let xcodeExtras: [[String]] = [
        ["Library", "Developer", "Xcode", "Archives"],
        ["Library", "Developer", "Xcode", "iOS DeviceSupport"],
        ["Library", "Developer", "Xcode", "macOS DeviceSupport"],
        ["Library", "Developer", "Xcode", "watchOS DeviceSupport"],
    ]

    /// Plain-named folders in ~/Library/Caches or ~/Library/Logs known to be third-party.
    /// Plain names not listed here are skipped, because many Apple folders use plain names.
    static let knownThirdParty: Set<String> = [
        "homebrew", "yarn", "pip", "pypoetry", "node-gyp", "mozilla", "firefox", "google",
        "bravesoftware", "microsoft edge", "arc", "vivaldi", "steam", "jetbrains", "spotify",
        "slack", "discord", "zoom.us", "sentrycrash", "claude-cli-nodejs", "chatgpthelper",
        "artcraft launcher", "updater", "typescript", "deno", "go-build", "golangci-lint",
        "cypress", "electron", "pnpm", "bun",
    ]

    static let browserRoots: [[String]] = [
        ["Google", "Chrome"], ["BraveSoftware", "Brave-Browser"], ["Microsoft Edge"],
        ["Arc", "User Data"], ["Vivaldi"],
    ]

    static let browserCacheParts: [[String]] = [
        ["Cache"], ["Code Cache"], ["GPUCache"], ["DawnCache"], ["DawnGraphiteCache"],
        ["DawnWebGPUCache"], ["GrShaderCache"], ["GraphiteDawnCache"], ["ShaderCache"],
        ["Service Worker", "CacheStorage"], ["Service Worker", "ScriptCache"],
    ]

    static let uninstallHomeRoots: [[String]] = [
        ["Applications"],
        ["Library", "Application Support"], ["Library", "Caches"], ["Library", "Preferences"],
        ["Library", "Containers"], ["Library", "Group Containers"],
        ["Library", "Saved Application State"], ["Library", "HTTPStorages"],
        ["Library", "WebKit"], ["Library", "Cookies"], ["Library", "Logs"],
        ["Library", "LaunchAgents"], ["Library", "Application Scripts"],
    ]

    static let uninstallSystemRoots: [[String]] = [
        ["Library", "LaunchAgents"], ["Library", "LaunchDaemons"],
        ["Library", "PrivilegedHelperTools"], ["Library", "Application Support"],
        ["Library", "Preferences"],
    ]

    // MARK: - Gate

    /// True if the item really lives inside the home folder (aliases like /var -> /private/var resolved).
    public func isInHome(_ url: URL) -> Bool {
        let path = Self.realPath(url.path)
            ?? Self.realPath(url.deletingLastPathComponent().path).map { $0 + "/" + url.lastPathComponent }
            ?? url.standardizedFileURL.path
        return path.hasPrefix(home + "/")
    }

    public func canTrash(_ url: URL, for purpose: Purpose) -> Bool {
        check(url, for: purpose).isAllowed
    }

    public func check(_ url: URL, for purpose: Purpose) -> Verdict {
        guard homeIsSane else { return .refused("home folder looks wrong") }
        let lexical = url.standardizedFileURL.path
        if Self.isSymlink(lexical) { return .refused("symlink") }
        guard let path = Self.realPath(lexical) else { return .refused("does not exist") }
        if path == "/" { return .refused("root volume") }
        let lowerPath = path.lowercased()
        if lowerPath.contains("com.apple") { return .refused("Apple item") }
        if let part = lowerPath.split(separator: "/").first(where: { c in Self.appleLegacyPrefixes.contains { c.hasPrefix($0) || c.hasPrefix("group." + $0) } }) {
            return .refused("macOS item: \(part)")
        }

        if let rel = Self.components(of: path, under: home) {
            return checkHome(rel, path: path, purpose: purpose)
        }
        if path == home { return .refused("home folder itself") }
        if Self.systemRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .refused("macOS system location")
        }
        return checkOutsideHome(path, purpose: purpose)
    }

    // MARK: - Home rules

    private func checkHome(_ rel: [String], path: String, purpose: Purpose) -> Verdict {
        if rel.isEmpty { return .refused("home folder itself") }
        switch purpose {
        case .clean:
            guard isCleanable(rel) else { return .refused("not a cleanable location") }
            if let bad = rel.first(where: Self.isProtectedName) {
                return .refused("protected: \(bad)")
            }
            if let bad = Self.protectedDescendant(of: path) {
                return .refused("contains protected data: \(bad)")
            }
            return .allowed
        case .reviewDownloads:
            return rel.count == 2 && rel[0] == "Downloads" ? .allowed : .refused("not a Downloads item")
        case .uninstall:
            for root in Self.uninstallHomeRoots where rel.count > root.count && rel.starts(with: root) {
                if root == ["Applications"] { return checkAppBundle(URL(fileURLWithPath: path)) }
                return .allowed
            }
            return .refused("not an app data location")
        case .devProjects:
            return checkDevProject(rel, path: path)
        case .userFiles:
            return checkUserFile(rel, path: path)
        }
    }

    private func checkDevProject(_ rel: [String], path: String) -> Verdict {
        for root in Self.xcodeExtras where rel.count > root.count && rel.starts(with: root) {
            return .allowed
        }
        guard let first = rel.first, first != "Library", !first.hasPrefix(".") else {
            return .refused("not inside a projects folder")
        }
        guard rel.count >= 3, let name = rel.last, let marker = Self.devJunk[name] else {
            return .refused("not a known build or dependency folder")
        }
        // Inside another junk folder (e.g. node_modules/foo/node_modules) is pointless and risky.
        if rel.dropLast().contains(where: { Self.devJunk[$0] != nil }) { return .refused("nested junk folder") }
        let url = URL(fileURLWithPath: path)
        let parts = marker.split(separator: ":", maxSplits: 1).map(String.init)
        let base = parts[0] == "self" ? url : url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: base.appendingPathComponent(parts[1]).path) else {
            return .refused("no \(parts[1]) next to it, so it may not be a project folder")
        }
        return .allowed
    }

    private func checkUserFile(_ rel: [String], path: String) -> Verdict {
        guard let first = rel.first else { return .refused("home folder itself") }
        if first == "Library" || first == "Applications" || first.hasPrefix(".") {
            return .refused("not a personal files location")
        }
        if rel.contains(where: { $0.hasPrefix(".") }) { return .refused("hidden folder") }
        if rel.contains("Mobile Documents") { return .refused("iCloud Drive") }
        if let bad = rel.first(where: { Self.packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return .refused("inside a library or app: \(bad)")
        }
        if rel.count == 1, FileSize.isDirectory(URL(fileURLWithPath: path)) {
            return .refused("a top-level folder in your home")
        }
        if let bad = rel.first(where: Self.isProtectedName) { return .refused("protected: \(bad)") }
        return .allowed
    }

    private func isCleanable(_ rel: [String]) -> Bool {
        if rel.count >= 3, rel.starts(with: ["Library", "Caches"]) {
            return Self.isThirdPartyOwner(rel[2])
        }
        if rel.count >= 3, rel.starts(with: ["Library", "Logs"]) {
            return rel[2] != "DiagnosticReports" && Self.isThirdPartyOwner(rel[2])
        }
        if rel.count >= 5, rel.starts(with: ["Library", "Developer", "Xcode", "DerivedData"]) {
            return true
        }
        for dev in [[".npm", "_cacache"], [".cache", "uv"], [".cache", "pip"]]
        where rel.count >= dev.count && rel.starts(with: dev) {
            return true
        }
        if rel.starts(with: ["Library", "Application Support"]) {
            return Self.isBrowserCache(Array(rel.dropFirst(2)))
        }
        return false
    }

    static func isBrowserCache(_ rel: [String]) -> Bool {
        for root in browserRoots where rel.starts(with: root) {
            let rest = Array(rel.dropFirst(root.count))
            for part in browserCacheParts {
                if rest.starts(with: part) { return true }                       // root-level cache
                if rest.count > part.count, Array(rest.dropFirst()).starts(with: part) {
                    return true                                                   // <profile>/cache
                }
            }
        }
        return false
    }

    /// Reverse-DNS names (not Apple) or a known third-party plain name.
    static func isThirdPartyOwner(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("com.apple") || lower.hasPrefix("apple") { return false }
        if knownThirdParty.contains(lower) { return true }
        let parts = lower.split(separator: ".")
        return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty }
    }

    static func isProtectedName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("cookie") || protectedNames.contains(lower)
    }

    /// Walks a directory and returns the first protected descendant, if any.
    static func protectedDescendant(of path: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
              let walker = FileManager.default.enumerator(atPath: path) else { return nil }
        while let item = walker.nextObject() as? String {
            let name = (item as NSString).lastPathComponent
            if isProtectedName(name) { return item }
        }
        return nil
    }

    // MARK: - Outside home (uninstall only)

    private func checkOutsideHome(_ path: String, purpose: Purpose) -> Verdict {
        guard purpose == .uninstall else { return .refused("outside home folder") }
        let comps = path.split(separator: "/").map(String.init)
        if comps.first == "Applications", comps.last?.hasSuffix(".app") == true,
           comps.count == 2 || comps.count == 3 {
            return checkAppBundle(URL(fileURLWithPath: path))
        }
        for root in Self.uninstallSystemRoots where comps.count > root.count && comps.starts(with: root) {
            return .allowed
        }
        return .refused("not an app data location")
    }

    private func checkAppBundle(_ url: URL) -> Verdict {
        guard url.pathExtension == "app" else { return .allowed } // leftover inside ~/Applications
        if let id = Bundle(url: url)?.bundleIdentifier, id.lowercased().hasPrefix("com.apple") {
            return .refused("Apple app")
        }
        if isAppleSigned(url) { return .refused("Apple-signed app") }
        return .allowed
    }

    // MARK: - Path helpers

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func isSymlink(_ path: String) -> Bool {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return attrs?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    static func components(of path: String, under root: String) -> [String]? {
        guard path.hasPrefix(root + "/") else { return nil }
        return path.dropFirst(root.count + 1).split(separator: "/").map(String.init)
    }
}
