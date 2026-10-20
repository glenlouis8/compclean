import Foundation

/// One item moved to the Trash: where it was, where it went, how big it was.
public struct Move: Sendable, Hashable {
    public let from: URL
    public let to: URL?
    public let size: Int64
    public let admin: Bool

    public init(from: URL, to: URL?, size: Int64, admin: Bool = false) {
        self.from = from
        self.to = to
        self.size = size
        self.admin = admin
    }
}

public struct TrashOutcome: Sendable {
    public var moves: [Move] = []
    public var refused: [(url: URL, reason: String)] = []
    public var failed: [(url: URL, reason: String)] = []
    /// Allowed but not writable as this user. Hand these to `PrivilegedRemover`.
    public var needsAdmin: [URL] = []

    public var trashed: [URL] { moves.map(\.from) }
    public var bytesFreed: Int64 { moves.reduce(0) { $0 + $1.size } }

    public init() {}

    public mutating func merge(_ other: TrashOutcome) {
        moves += other.moves
        refused += other.refused
        failed += other.failed
        needsAdmin += other.needsAdmin
    }
}

/// The only code that moves files. Every item is re-checked against the policy
/// right before it moves, and everything goes to the Trash, never deleted.
public struct Trasher: Sendable {
    public let policy: SafetyPolicy
    public let log: ActionLog
    /// Moves one item to the Trash and returns where it landed. Tests swap in a fake Trash.
    public let mover: @Sendable (URL) throws -> URL?

    public init(policy: SafetyPolicy, log: ActionLog = ActionLog(),
                mover: @escaping @Sendable (URL) throws -> URL? = Trasher.systemTrash) {
        self.policy = policy
        self.log = log
        self.mover = mover
    }

    public static let systemTrash: @Sendable (URL) throws -> URL? = { url in
        var landed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        return landed as URL?
    }

    public func trash(_ items: [(url: URL, size: Int64)], purpose: Purpose) -> TrashOutcome {
        var outcome = TrashOutcome()
        for item in items {
            let verdict = policy.check(item.url, for: purpose)
            guard verdict.isAllowed else {
                if case .refused(let reason) = verdict { outcome.refused.append((item.url, reason)) }
                log.write("REFUSED \(item.url.path) (\(verdict))")
                continue
            }
            do {
                let landed = try mover(item.url)
                outcome.moves.append(Move(from: item.url, to: landed, size: item.size))
                log.write("TRASHED \(item.url.path) \(item.size)")
            } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                outcome.needsAdmin.append(item.url)
            } catch {
                outcome.failed.append((item.url, error.localizedDescription))
                log.write("FAILED \(item.url.path): \(error.localizedDescription)")
            }
        }
        return outcome
    }

    public func trash(_ findings: [Finding]) -> TrashOutcome {
        var outcome = TrashOutcome()
        for category in CleanCategory.allCases {
            let group = findings.filter { $0.category == category }
            guard !group.isEmpty else { continue }
            outcome.merge(trash(group.map { ($0.url, $0.size) }, purpose: category.purpose))
        }
        return outcome
    }

    public func trash(_ items: [ReviewItem]) -> TrashOutcome {
        var outcome = TrashOutcome()
        for purpose in Set(items.map(\.purpose)) {
            outcome.merge(trash(items.filter { $0.purpose == purpose }.map { ($0.url, $0.size) }, purpose: purpose))
        }
        return outcome
    }
}

/// Append-only record of every action, at ~/Library/Logs/CompClean/actions.log.
public struct ActionLog: Sendable {
    public let url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CompClean/actions.log")) {
        self.url = url
    }

    public func write(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
