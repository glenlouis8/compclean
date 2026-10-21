import AppKit
import CleanerCore
import SwiftUI

/// State for one finder screen: scan, review, move to Trash, record in History.
@MainActor
final class FinderStore: ObservableObject {
    let feature: String
    /// Builds the search on the main actor (reading settings), then it runs in the background.
    private let makeFinder: @MainActor () -> @Sendable () -> [ReviewItem]
    private let prepare: (@Sendable ([ReviewItem]) -> Void)?
    private let policy: SafetyPolicy
    private let log: ActionLog
    private let history: HistoryStore
    private let onFreed: (Int64) -> Void

    @Published var items: [ReviewItem] = []
    @Published var selection: Set<String> = []
    @Published var isScanning = false
    @Published var isTrashing = false
    @Published var hasScanned = false
    @Published var message: String?

    init(feature: String, policy: SafetyPolicy, log: ActionLog, history: HistoryStore,
         prepare: (@Sendable ([ReviewItem]) -> Void)? = nil,
         onFreed: @escaping (Int64) -> Void,
         finder: @escaping @MainActor () -> @Sendable () -> [ReviewItem]) {
        self.feature = feature
        self.makeFinder = finder
        self.prepare = prepare
        self.policy = policy
        self.log = log
        self.history = history
        self.onFreed = onFreed
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        message = nil
        let finder = makeFinder()
        let found = await Task.detached { finder() }.value
        items = found
        selection = Set(found.filter(\.preselected).map(\.id))
        hasScanned = true
        isScanning = false
    }

    func trashSelected() async {
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        isTrashing = true
        let trasher = Trasher(policy: policy, log: log)
        let prepare = prepare
        let outcome = await Task.detached {
            prepare?(chosen)
            return trasher.trash(chosen)
        }.value
        history.record(feature: feature, moves: outcome.moves,
                       titles: Dictionary(chosen.map { ($0.url, $0.explanation.title) }, uniquingKeysWith: { a, _ in a }))
        let gone = Set(outcome.trashed.map(\.path))
        items.removeAll { gone.contains($0.id) }
        selection.subtract(gone)
        onFreed(outcome.bytesFreed)
        var msg = "Moved \(outcome.moves.count) items (\(ByteFormat.string(outcome.bytesFreed))) to the Trash."
        if !outcome.refused.isEmpty { msg += " \(outcome.refused.count) blocked by safety rules." }
        if !outcome.failed.isEmpty || !outcome.needsAdmin.isEmpty {
            msg += " \(outcome.failed.count + outcome.needsAdmin.count) couldn't be moved (macOS may protect them)."
        }
        message = msg
        isTrashing = false
    }
}

/// Header card + explained review list, shared by every finder screen.
struct FinderScreen<Extra: View>: View {
    @ObservedObject var store: FinderStore
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var emptyText = "Nothing found. Nice and tidy."
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: 0) {
            header.probe("page header")
            if store.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Looking…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.hasScanned {
                ContentUnavailableView {
                    Label(title, systemImage: symbol)
                } description: {
                    Text(subtitle)
                } actions: {
                    Button("Look now") { Task { await store.scan() } }.buttonStyle(.glassProminent).controlSize(.large)
                }
                .frame(maxHeight: .infinity)
            } else {
                ReviewList(items: store.items, selection: $store.selection, isWorking: store.isTrashing,
                           emptyText: emptyText) {
                    Task { await store.trashSelected() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .bold)).tracking(-0.3)
                Text(store.message ?? (store.hasScanned
                    ? "Found \(ByteFormat.string(store.totalBytes)) in \(store.items.count) items. Click › on any row to see what it is."
                    : subtitle))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            extra
            if store.hasScanned {
                Button {
                    Task { await store.scan() }
                } label: { Label("Look again", systemImage: "arrow.clockwise") }
                .buttonStyle(.glass)
                .disabled(store.isScanning || store.isTrashing)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }
}

extension FinderScreen where Extra == EmptyView {
    init(store: FinderStore, title: String, subtitle: String, symbol: String, color: Color,
         emptyText: String = "Nothing found. Nice and tidy.") {
        self.init(store: store, title: title, subtitle: subtitle, symbol: symbol, color: color,
                  emptyText: emptyText) { EmptyView() }
    }
}

#if DEBUG
#Preview("Leftovers") {
    let m = PreviewData.leftoversModel()
    return FinderScreen(store: m.leftoversStore, title: "Leftovers",
                        subtitle: "Files that apps you already deleted left in your Library.",
                        symbol: "shippingbox", color: .blue)
        .previewEnvironment(m)
}
#endif
