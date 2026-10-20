import CoreServices
import Foundation
import UniformTypeIdentifiers

/// Finds your own large files, grouped by how long ago you last opened them. Nothing is pre-ticked.
public struct LargeFileFinder: Sendable {
    public let policy: SafetyPolicy
    public let home: URL
    public let minBytes: Int64
    public let useSpotlight: Bool
    public let now: Date

    public init(policy: SafetyPolicy, minMB: Int = 500, useSpotlight: Bool = true, now: Date = Date()) {
        self.policy = policy
        self.home = URL(fileURLWithPath: policy.home)
        self.minBytes = Int64(minMB) * 1_000_000
        self.useSpotlight = useSpotlight
        self.now = now
    }

    public func find() -> [ReviewItem] {
        var paths = useSpotlight ? spotlightSearch() : []
        if paths.isEmpty { paths = walk() }
        let items = Set(paths).compactMap(item)
        let order = ["Not opened in over a year", "Not opened in 6+ months", "Opened in the last 6 months"]
        return items.sorted { a, b in
            let ga = order.firstIndex(of: a.group) ?? 9, gb = order.firstIndex(of: b.group) ?? 9
            return ga != gb ? ga < gb : a.size > b.size
        }
    }

    private func item(_ path: String) -> ReviewItem? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true,
              Int64(v.fileSize ?? 0) >= minBytes,
              policy.canTrash(url, for: .userFiles) else { return nil }
        let used = Self.lastOpened(url)
        let days = used.map { now.timeIntervalSince($0) / 86_400 } ?? .infinity
        let group = days > 365 ? "Not opened in over a year" : days > 182 ? "Not opened in 6+ months" : "Opened in the last 6 months"
        let kind = UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "File"
        let folder = url.deletingLastPathComponent().path.replacingOccurrences(of: policy.home, with: "~")
        return ReviewItem(
            url: url, size: Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0),
            explanation: Explanation(
                title: url.lastPathComponent, safety: .yourFile,
                reason: "\(kind.prefix(1).uppercased() + kind.dropFirst()) in \(folder). This is your own file. CompClean can't know if you still need it, so only remove it if you're sure.",
                lastUsed: used),
            group: group, preselected: false, purpose: .userFiles)
    }

    /// Last opened date from Spotlight, falling back to the file's access date.
    static func lastOpened(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let d = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { return d }
        return ItemExplainer.lastUsed(url)
    }

    private func spotlightSearch() -> [String] {
        Shell.run("/usr/bin/mdfind", ["-onlyin", home.path, "kMDItemFSSize > \(minBytes)"])
            .split(separator: "\n").map(String.init)
    }

    /// Used when Spotlight is off or for tests: walks personal folders only.
    private func walk() -> [String] {
        var out: [String] = []
        for top in FileSize.children(home) where !top.lastPathComponent.hasPrefix(".")
            && !["Library", "Applications"].contains(top.lastPathComponent) {
            if !FileSize.isDirectory(top) {
                out.append(top.path)
                continue
            }
            guard let walker = FileManager.default.enumerator(
                at: top, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = walker.nextObject() as? URL {
                let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true, Int64(v?.fileSize ?? 0) >= minBytes { out.append(url.path) }
            }
        }
        return out
    }
}
