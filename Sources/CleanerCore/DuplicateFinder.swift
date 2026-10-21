import CryptoKit
import Foundation

/// Finds byte-for-byte identical files. Suggests keeping the newest copy; nothing is pre-ticked.
public struct DuplicateFinder: Sendable {
    public let policy: SafetyPolicy
    public let folders: [URL]
    public let minBytes: Int64

    public init(policy: SafetyPolicy, folders: [URL]? = nil, minMB: Double = 1) {
        self.policy = policy
        let home = URL(fileURLWithPath: policy.home)
        self.folders = folders ?? Self.defaultFolders(home: home)
        self.minBytes = Int64(minMB * 1_000_000)
    }

    public static func defaultFolders(home: URL) -> [URL] {
        ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }.filter(FileSize.isDirectory)
    }

    struct Candidate {
        let url: URL
        let size: Int64
        let allocated: Int64
        let modified: Date
        let contentID: Int64?
        let inode: String?
    }

    public func find() -> [ReviewItem] {
        let bySize = Dictionary(grouping: collect(), by: \.size).values.filter { $0.count > 1 }
        var items: [ReviewItem] = []
        for sameSize in bySize {
            for partial in Dictionary(grouping: sameSize, by: { Self.quickHash($0.url) }).values where partial.count > 1 {
                for group in Dictionary(grouping: partial, by: { Self.fullHash($0.url) }).values where group.count > 1 {
                    items += reviewItems(for: Self.distinctStorage(group))
                }
            }
        }
        // Groups with the most space to win first.
        let wins = Dictionary(grouping: items, by: \.group).mapValues { g in g.filter { !$0.isKeeper }.reduce(0) { $0 + $1.size } }
        return items.sorted { a, b in
            let wa = wins[a.group] ?? 0, wb = wins[b.group] ?? 0
            if wa != wb { return wa > wb }
            if a.group != b.group { return a.group < b.group }
            return a.isKeeper && !b.isKeeper
        }
    }

    private func reviewItems(for group: [Candidate]) -> [ReviewItem] {
        guard group.count > 1 else { return [] }
        let sorted = group.sorted { $0.modified > $1.modified }
        let keeper = sorted[0]
        let keptAt = keeper.url.path.replacingOccurrences(of: policy.home, with: "~")
        let name = "\(keeper.url.lastPathComponent) · \(group.count) copies"
        return sorted.enumerated().map { i, c in
            ReviewItem(
                url: c.url, size: c.allocated,
                explanation: Explanation(
                    title: c.url.lastPathComponent, safety: .yourFile,
                    reason: i == 0
                        ? "The newest copy. Suds suggests keeping this one."
                        : "Exactly the same contents as \(keptAt), byte for byte. Removing this copy keeps the other.",
                    lastUsed: c.modified),
                group: name, preselected: false, purpose: .userFiles, isKeeper: i == 0)
        }
    }

    /// Hard links and APFS clones share storage, so removing one frees nothing. Keep one per storage.
    static func distinctStorage(_ group: [Candidate]) -> [Candidate] {
        var seen: Set<String> = []
        return group.filter { c in
            let key = c.inode.map { "i:\($0)" } ?? c.contentID.map { "c:\($0)" } ?? "u:\(c.url.path)"
            let clone = c.contentID.map { "c:\($0)" }
            defer { seen.insert(key); if let clone { seen.insert(clone) } }
            return !seen.contains(key) && !(clone.map(seen.contains) ?? false)
        }
    }

    private func collect() -> [Candidate] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
                                         .contentModificationDateKey, .fileContentIdentifierKey, .fileResourceIdentifierKey,
                                         .isSymbolicLinkKey]
        var out: [Candidate] = []
        for folder in folders {
            guard let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let url = walker.nextObject() as? URL {
                guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true, v.isSymbolicLink != true,
                      let size = v.fileSize, Int64(size) >= minBytes,
                      policy.canTrash(url, for: .userFiles) else { continue }
                out.append(Candidate(
                    url: url, size: Int64(size), allocated: Int64(v.totalFileAllocatedSize ?? size),
                    modified: v.contentModificationDate ?? .distantPast,
                    contentID: v.fileContentIdentifier,
                    inode: v.fileResourceIdentifier.map { "\($0)" }))
            }
        }
        return out
    }

    /// SHA-256 of the first and last 64 KB. Cheap way to split same-size files.
    static func quickHash(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "unreadable:\(url.path)" }
        defer { try? h.close() }
        var hasher = SHA256()
        if let head = try? h.read(upToCount: 65_536) { hasher.update(data: head) }
        if let end = try? h.seekToEnd(), end > 131_072 {
            try? h.seek(toOffset: end - 65_536)
            if let tail = try? h.read(upToCount: 65_536) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "unreadable:\(url.path)" }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
