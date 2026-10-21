import AppKit
import CleanerCore
import SwiftUI

/// Every clean and uninstall, item by item, with Put back.
struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var model: AppModel
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header.probe("page header")
            if history.sessions.isEmpty {
                ContentUnavailableView("Nothing removed yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Every time Suds moves something to the Trash, it's listed here so you can put it back."))
            } else {
                List {
                    ForEach(history.sessions) { session in
                        Section { sessionBody(session) } header: { sessionHeader(session) }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { history.refresh() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "clock.arrow.circlepath", color: .green, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("History").font(.system(size: 24, weight: .bold)).tracking(-0.3)
                Text(history.message ?? "Everything Suds moved to the Trash. Put back anything that's still there.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: model.policy.home + "/.Trash")) }
                .buttonStyle(.glass)
            Button("Action log") { NSWorkspace.shared.activateFileViewerSelecting([model.log.url]) }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func sessionHeader(_ s: LedgerSession) -> some View {
        HStack(spacing: 8) {
            Text(s.feature).fontWeight(.semibold)
            Text(s.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
            Spacer()
            Text("\(s.entries.count) items · \(ByteFormat.string(s.bytes))").monospacedDigit().foregroundStyle(.secondary)
            if history.canPutBack(s) {
                Button("Put back all") { Task { await history.putBack(s.entries) } }
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(history.isWorking)
            }
        }
        .font(.callout)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func sessionBody(_ s: LedgerSession) -> some View {
        let shown = expanded.contains(s.id) ? s.entries : Array(s.entries.prefix(5))
        ForEach(shown) { entry in EntryRow(entry: entry) }
        if s.entries.count > 5 {
            Button(expanded.contains(s.id) ? "Show less" : "Show all \(s.entries.count)") {
                withAnimation(.ui) {
                    if expanded.contains(s.id) { expanded.remove(s.id) } else { expanded.insert(s.id) }
                }
            }
            .buttonStyle(.link)
        }
    }
}

struct EntryRow: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var model: AppModel
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.trashed ?? entry.original))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title).lineLimit(1)
                    if entry.admin {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                            .help("Needs your password to put back")
                    }
                }
                Text(entry.original.replacingOccurrences(of: model.policy.home, with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(ByteFormat.string(entry.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            statusView
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var statusView: some View {
        switch history.status(entry) {
        case .inTrash:
            Button("Put back") { Task { await history.putBack([entry]) } }
                .buttonStyle(.glass).controlSize(.small)
                .disabled(history.isWorking)
        case .restored:
            Label("Put back", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .emptied:
            Text("Trash emptied").font(.caption).foregroundStyle(.secondary)
        }
    }
}
