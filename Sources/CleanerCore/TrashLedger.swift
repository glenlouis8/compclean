import Foundation

/// One removed item, as remembered for the History screen.
public struct LedgerEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var original: String
    public var trashed: String?
    public var size: Int64
    public var title: String
    public var admin: Bool
    public var restoredAt: Date?
}

/// One clean or uninstall run.
public struct LedgerSession: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var feature: String
    public var entries: [LedgerEntry]

    public var bytes: Int64 { entries.reduce(0) { $0 + $1.size } }
}

public enum EntryStatus: Sendable, Equatable {
    case inTrash, restored, emptied
}

public enum PutBackResult: Sendable, Equatable {
    case restored(URL)
    case needsAdmin
    case gone
    case failed(String)
}

/// Remembers what was moved to the Trash so it can be shown and put back.
/// Stored as JSON at ~/Library/Application Support/Suds/history.json.
public final class TrashLedger: @unchecked Sendable {
    public let url: URL
    public let home: String
    private let lock = NSLock()

    public init(home: String = SafetyPolicy().home, url: URL? = nil) {
        self.home = home
        self.url = url ?? URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/Suds/history.json")
    }

    public func sessions() -> [LedgerSession] {
        lock.lock(); defer { lock.unlock() }
        return read()
    }

    @discardableResult
    public func record(feature: String, moves: [Move], titles: [URL: String] = [:]) -> LedgerSession? {
        guard !moves.isEmpty else { return nil }
        let session = LedgerSession(
            id: UUID(), date: Date(), feature: feature,
            entries: moves.map {
                LedgerEntry(id: UUID(), original: $0.from.path, trashed: $0.to?.path, size: $0.size,
                            title: titles[$0.from] ?? $0.from.lastPathComponent, admin: $0.admin, restoredAt: nil)
            })
        lock.lock(); defer { lock.unlock() }
        var all = read()
        all.insert(session, at: 0)
        write(Array(all.prefix(200)))
        return session
    }

    public func status(of entry: LedgerEntry) -> EntryStatus {
        if entry.restoredAt != nil { return .restored }
        guard let trashed = entry.trashed, FileManager.default.fileExists(atPath: trashed) else { return .emptied }
        return .inTrash
    }

    /// Moves the item back to its original folder. A name clash gets " (restored)" added.
    public func putBack(_ entry: LedgerEntry) -> PutBackResult {
        guard status(of: entry) == .inTrash, let trashedPath = entry.trashed else { return .gone }
        let trashed = URL(fileURLWithPath: trashedPath)
        guard (SafetyPolicy.realPath(trashedPath) ?? trashedPath).hasPrefix(home + "/.Trash/") else {
            return .failed("Not in your Trash")
        }
        let dest = Self.freeDestination(for: URL(fileURLWithPath: entry.original))
        if entry.admin { return .needsAdmin }
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: trashed, to: dest)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            return .needsAdmin
        } catch {
            return .failed(error.localizedDescription)
        }
        markRestored([entry.id])
        return .restored(dest)
    }

    public func markRestored(_ ids: [UUID]) {
        lock.lock(); defer { lock.unlock() }
        var all = read()
        let now = Date()
        for s in all.indices {
            for e in all[s].entries.indices where ids.contains(all[s].entries[e].id) {
                all[s].entries[e].restoredAt = now
            }
        }
        write(all)
    }

    /// The original path, or "name (restored).ext" beside it if something new already lives there.
    static func freeDestination(for original: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: original.path) else { return original }
        let ext = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let name = n == 1 ? "\(stem) (restored)" : "\(stem) (restored \(n))"
            let candidate = original.deletingLastPathComponent()
                .appendingPathComponent(ext.isEmpty ? name : "\(name).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    private func read() -> [LedgerSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([LedgerSession].self, from: data)) ?? []
    }

    private func write(_ sessions: [LedgerSession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
