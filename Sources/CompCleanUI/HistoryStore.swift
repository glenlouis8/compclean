import CleanerCore
import SwiftUI

/// Everything CompClean has moved to the Trash, and putting it back.
@MainActor
final class HistoryStore: ObservableObject {
    let ledger: TrashLedger
    let policy: SafetyPolicy
    let log: ActionLog

    @Published var sessions: [LedgerSession] = []
    @Published var statuses: [UUID: EntryStatus] = [:]
    @Published var message: String?
    @Published var isWorking = false

    init(ledger: TrashLedger, policy: SafetyPolicy, log: ActionLog) {
        self.ledger = ledger
        self.policy = policy
        self.log = log
        refresh()
    }

    func refresh() {
        sessions = ledger.sessions()
        var s: [UUID: EntryStatus] = [:]
        for session in sessions { for e in session.entries { s[e.id] = ledger.status(of: e) } }
        statuses = s
    }

    func record(feature: String, moves: [Move], titles: [URL: String]) {
        ledger.record(feature: feature, moves: moves, titles: titles)
        refresh()
    }

    func status(_ entry: LedgerEntry) -> EntryStatus { statuses[entry.id] ?? .emptied }

    func canPutBack(_ session: LedgerSession) -> Bool {
        session.entries.contains { status($0) == .inTrash }
    }

    func putBack(_ entries: [LedgerEntry]) async {
        isWorking = true
        defer { isWorking = false }
        let ledger = ledger
        let waiting = entries.filter { status($0) == .inTrash }
        let results = await Task.detached { waiting.map { ($0, ledger.putBack($0)) } }.value

        var restored = results.filter { if case .restored = $0.1 { true } else { false } }.count
        let admin = results.filter { $0.1 == .needsAdmin }.map(\.0)
        let failed = results.filter { if case .failed = $0.1 { true } else { false } }.count

        if !admin.isEmpty {
            let pairs = admin.compactMap { e in e.trashed.map { (URL(fileURLWithPath: $0), URL(fileURLWithPath: e.original)) } }
            let remover = PrivilegedRemover(policy: policy, log: log)
            let failure = await Task.detached { remover.putBack(pairs.map { (trashed: $0.0, original: $0.1) }) }.value
            if failure == nil {
                ledger.markRestored(admin.map(\.id))
                restored += admin.count
            }
        }
        for (entry, result) in results { if case .restored = result { log.write("PUT BACK \(entry.original)") } }
        message = failed > 0 ? "Put back \(restored) items. \(failed) couldn't be moved." : "Put back \(restored) items."
        refresh()
    }
}
