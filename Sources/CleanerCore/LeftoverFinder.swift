import Foundation

public enum MatchKind: String, Sendable {
    case app          // the .app bundle itself
    case bundleID     // name is the app's bundle id
    case appName      // name equals the app's name
    case team         // group container of the same developer team
    case company      // same vendor prefix, e.g. com.docker.*
    case receipt      // listed in the app's installer receipt

    public var label: String {
        switch self {
        case .app: "App"
        case .bundleID: "Bundle ID match"
        case .appName: "Name match"
        case .team: "Same developer"
        case .company: "Same vendor"
        case .receipt: "Installer receipt"
        }
    }

    /// Exact matches are pre-selected. Looser matches are shown but left for you to tick.
    public var preselected: Bool { self == .app || self == .bundleID || self == .appName }
}

public struct Leftover: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let match: MatchKind
    public let needsAdmin: Bool

    public init(url: URL, size: Int64, match: MatchKind, needsAdmin: Bool) {
        self.url = url
        self.size = size
        self.match = match
        self.needsAdmin = needsAdmin
    }
}

public struct LeftoverFinder: Sendable {
    public let policy: SafetyPolicy
    public let home: URL
    public let systemLibrary: URL
    public let readReceipts: Bool

    public init(policy: SafetyPolicy, systemLibrary: URL = URL(fileURLWithPath: "/Library"), readReceipts: Bool = true) {
        self.policy = policy
        self.home = URL(fileURLWithPath: policy.home)
        self.systemLibrary = systemLibrary
        self.readReceipts = readReceipts
    }

    static let userRoots = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers",
        "Group Containers", "Saved Application State", "HTTPStorages", "WebKit", "Cookies",
        "Logs", "LaunchAgents", "Application Scripts",
    ]
    static let systemRoots = [
        "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools", "Application Support", "Preferences",
    ]
    static let suffixes = [".plist", ".savedstate", ".binarycookies", ".app"]

    public func find(for app: AppInfo) -> [Leftover] {
        guard !app.isApple else { return [] }
        var found: [URL: MatchKind] = [app.url: .app]

        let lib = home.appendingPathComponent("Library")
        for root in Self.userRoots {
            for child in FileSize.children(lib.appendingPathComponent(root)) {
                if let kind = match(child.lastPathComponent, app: app) { found[child] = found[child] ?? kind }
            }
        }
        for root in Self.systemRoots {
            for child in FileSize.children(systemLibrary.appendingPathComponent(root)) {
                if let kind = match(child.lastPathComponent, app: app) { found[child] = found[child] ?? kind }
            }
        }
        if readReceipts {
            for url in receiptItems(for: app) where found[url] == nil { found[url] = .receipt }
        }

        return found.compactMap { url, kind -> Leftover? in
            guard policy.canTrash(url, for: .uninstall) else { return nil }
            let inHome = policy.isInHome(url)
            let writable = FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
            return Leftover(url: url, size: FileSize.allocated(url), match: kind, needsAdmin: !inHome || !writable)
        }
        .sorted { ($0.match.preselected ? 0 : 1, -$0.size) < ($1.match.preselected ? 0 : 1, -$1.size) }
    }

    func match(_ rawName: String, app: AppInfo) -> MatchKind? {
        let name = rawName.lowercased()
        // The name as-is and with one known suffix removed. Strip once only: ids can end in ".app".
        let stems = [name] + Self.suffixes.filter { name.hasSuffix($0) }.map { String(name.dropLast($0.count)) }
        let id = app.bundleID.lowercased()
        let appName = app.name.lowercased()

        if stems.contains(where: { $0 == id || $0.hasSuffix("." + id) || $0 == "group." + id }) || name.hasPrefix(id + ".") {
            return .bundleID
        }
        if appName.count >= 4,
           stems.contains(where: { $0 == appName || $0 == appName.replacingOccurrences(of: " ", with: "") }) {
            return .appName
        }
        if let team = app.teamID?.lowercased(), !team.isEmpty, name.hasPrefix(team + ".") {
            return .team
        }
        let parts = id.split(separator: ".")
        if parts.count >= 3 {
            let company = parts.prefix(2).joined(separator: ".")
            if company != "com.apple", name.hasPrefix(company + ".") { return .company }
        }
        return nil
    }

    /// Top-level items recorded in installer receipts that mention this app.
    /// Receipts are only read; they live in a macOS folder and are never changed.
    func receiptItems(for app: AppInfo) -> [URL] {
        let id = app.bundleID.lowercased()
        let pkgs = Shell.run("/usr/sbin/pkgutil", ["--pkgs"]).split(separator: "\n").map(String.init)
            .filter { $0.lowercased().hasPrefix(id) || $0.lowercased().contains("." + id) }
        var out: Set<URL> = []
        for pkg in pkgs {
            for line in Shell.run("/usr/sbin/pkgutil", ["--files", pkg]).split(separator: "\n") {
                let comps = line.split(separator: "/").map(String.init)
                let top: [String]?
                if comps.count >= 3, comps[0] == "Library", Self.systemRoots.contains(comps[1]) {
                    top = Array(comps.prefix(3))
                } else if comps.count >= 2, comps[0] == "Applications", comps[1].hasSuffix(".app") {
                    top = Array(comps.prefix(2))
                } else {
                    top = nil
                }
                guard let top else { continue }
                let url = URL(fileURLWithPath: "/" + top.joined(separator: "/"))
                if FileManager.default.fileExists(atPath: url.path) { out.insert(url) }
            }
        }
        return Array(out)
    }
}

enum Shell {
    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
