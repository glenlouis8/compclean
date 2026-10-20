import Foundation

/// Finds dependency and build folders in code projects you haven't touched in a while,
/// plus Xcode archives and device support files.
public struct DevJunkFinder: Sendable {
    public let policy: SafetyPolicy
    public let home: URL
    public let roots: [URL]
    public let staleAge: TimeInterval
    public let now: Date

    public init(policy: SafetyPolicy, roots: [URL]? = nil, staleDays: Int = 30, now: Date = Date()) {
        self.policy = policy
        self.home = URL(fileURLWithPath: policy.home)
        self.roots = roots ?? Self.defaultRoots(home: URL(fileURLWithPath: policy.home))
        self.staleAge = TimeInterval(staleDays) * 86_400
        self.now = now
    }

    public static let rootNames = ["Coding", "Developer", "Projects", "code", "src", "dev", "repos",
                                   "workspace", "GitHub", "Documents/GitHub", "Documents/Projects"]

    public static func defaultRoots(home: URL) -> [URL] {
        rootNames.map { home.appendingPathComponent($0) }.filter(FileSize.isDirectory)
    }

    struct Kind {
        let group: String
        let what: String
        let restore: String
        let preselect: Bool
    }

    static let kinds: [String: Kind] = [
        "node_modules": Kind(group: "JavaScript packages (node_modules)", what: "Downloaded npm packages",
                             restore: "Run npm install (or yarn / pnpm install) to get them back.", preselect: true),
        ".venv": Kind(group: "Python environments", what: "A Python virtual environment",
                      restore: "Recreate it with python -m venv and reinstall from requirements. Anything you pip-installed by hand is lost.", preselect: false),
        "venv": Kind(group: "Python environments", what: "A Python virtual environment",
                     restore: "Recreate it with python -m venv and reinstall from requirements. Anything you pip-installed by hand is lost.", preselect: false),
        "target": Kind(group: "Rust build output (target)", what: "Compiled Rust build files",
                       restore: "cargo build recreates it.", preselect: true),
        ".build": Kind(group: "Swift build output (.build)", what: "Compiled Swift package build files",
                       restore: "swift build recreates it.", preselect: true),
        ".terraform": Kind(group: "Terraform providers (.terraform)", what: "Downloaded Terraform providers and modules",
                           restore: "terraform init downloads them again. Your state files are not in here.", preselect: true),
    ]

    static let maxDepth = 6

    public func find() -> [ReviewItem] {
        var items: [ReviewItem] = []
        for root in roots { items += scan(root) }
        items += xcodeExtras()
        return items.sorted { a, b in a.group != b.group ? a.group < b.group : a.size > b.size }
    }

    private func scan(_ root: URL) -> [ReviewItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                          options: [.skipsPackageDescendants]) else { return [] }
        let baseDepth = root.pathComponents.count
        var out: [ReviewItem] = []
        while let url = walker.nextObject() as? URL {
            let v = try? url.resourceValues(forKeys: Set(keys))
            guard v?.isDirectory == true, v?.isSymbolicLink != true else { continue }
            let name = url.lastPathComponent
            if url.pathComponents.count - baseDepth >= Self.maxDepth { walker.skipDescendants(); continue }
            if let kind = Self.kinds[name] {
                walker.skipDescendants()
                guard policy.canTrash(url, for: .devProjects) else { continue }
                let project = url.deletingLastPathComponent()
                let touched = Self.lastTouched(project)
                guard let touched, now.timeIntervalSince(touched) > staleAge else { continue }
                let size = FileSize.allocated(url)
                guard size > 0 else { continue }
                let ago = RelativeDateTimeFormatter().localizedString(for: touched, relativeTo: now)
                out.append(ReviewItem(
                    url: url, size: size,
                    explanation: Explanation(
                        title: "\(project.lastPathComponent) · \(name)", safety: .reviewFirst,
                        reason: "\(kind.what) for the project \(project.lastPathComponent), which you last changed \(ago). \(kind.restore)",
                        lastUsed: touched),
                    group: kind.group, preselected: kind.preselect, purpose: .devProjects))
            } else if name.hasPrefix(".") || name == "Library" {
                walker.skipDescendants() // .git, .idea and friends
            }
        }
        return out
    }

    /// Newest change among a project's own files (not its junk folders), looking a few levels deep.
    static func lastTouched(_ project: URL) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: project, includingPropertiesForKeys: keys,
                                                          options: [.skipsPackageDescendants]) else { return nil }
        let base = project.pathComponents.count
        var newest: Date?
        var seen = 0
        while let url = walker.nextObject() as? URL, seen < 20_000 {
            seen += 1
            let name = url.lastPathComponent
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                if kinds[name] != nil || (name.hasPrefix(".") && name != ".github")
                    || url.pathComponents.count - base >= 4 {
                    walker.skipDescendants()
                }
                continue
            }
            if let d = v?.contentModificationDate, d > (newest ?? .distantPast) { newest = d }
        }
        return newest
    }

    private func xcodeExtras() -> [ReviewItem] {
        let xcode = home.appendingPathComponent("Library/Developer/Xcode")
        var out: [ReviewItem] = []
        for archive in FileSize.children(xcode.appendingPathComponent("Archives")).filter(FileSize.isDirectory) {
            for item in FileSize.children(archive) where policy.canTrash(item, for: .devProjects) {
                out.append(ReviewItem(
                    url: item, size: FileSize.allocated(item),
                    explanation: Explanation(
                        title: "Xcode archive · \(item.deletingPathExtension().lastPathComponent)", safety: .reviewFirst,
                        reason: "A saved build you made for distribution. Keep it if you might need to debug crash reports for that release.",
                        lastUsed: ItemExplainer.lastUsed(item)),
                    group: "Xcode archives", preselected: false, purpose: .devProjects))
            }
        }
        for platform in ["iOS DeviceSupport", "macOS DeviceSupport", "watchOS DeviceSupport"] {
            for item in FileSize.children(xcode.appendingPathComponent(platform))
            where FileSize.isDirectory(item) && policy.canTrash(item, for: .devProjects) {
                let used = ItemExplainer.lastUsed(item)
                out.append(ReviewItem(
                    url: item, size: FileSize.allocated(item),
                    explanation: Explanation(
                        title: "\(platform.replacingOccurrences(of: " DeviceSupport", with: "")) \(item.lastPathComponent) device files",
                        safety: .rebuildsItself,
                        reason: "Debug files Xcode copied from a device running this OS version. Xcode copies them again the next time you connect that device.",
                        lastUsed: used),
                    group: "Xcode device support",
                    preselected: used.map { now.timeIntervalSince($0) > 90 * 86_400 } ?? true,
                    purpose: .devProjects))
            }
        }
        return out
    }
}

/// Developer tools with their own cleanup commands. These can't be put back, so the UI says so.
public enum DevTools {
    public static var xcrunAvailable: Bool { FileManager.default.fileExists(atPath: "/usr/bin/xcrun") }

    /// Number of simulators for runtimes that are no longer installed.
    public static func unavailableSimulatorCount() -> Int {
        guard xcrunAvailable else { return 0 }
        let out = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"])
        guard let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return 0 }
        return devices.values.reduce(0) { $0 + $1.count }
    }

    public static func deleteUnavailableSimulators() {
        Shell.run("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])
    }

    static let dockerPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker",
                              "/Applications/Docker.app/Contents/Resources/bin/docker"]

    public static var dockerPath: String? { dockerPaths.first { FileManager.default.fileExists(atPath: $0) } }

    /// Reclaimable space Docker reports, e.g. "4.2GB", or nil if Docker isn't running.
    public static func dockerReclaimable() -> String? {
        guard let docker = dockerPath else { return nil }
        let out = Shell.run(docker, ["system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"])
        let lines = out.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
        guard !lines.isEmpty else { return nil }
        return lines.compactMap { $0.count == 2 ? "\($0[0]): \($0[1])" : nil }.joined(separator: " · ")
    }

    /// Removes stopped containers, unused networks, dangling images and build cache. Not undoable.
    public static func dockerPrune() -> String {
        guard let docker = dockerPath else { return "Docker isn't installed." }
        let out = Shell.run(docker, ["system", "prune", "--force"])
        return out.split(separator: "\n").last.map(String.init) ?? "Done."
    }
}
