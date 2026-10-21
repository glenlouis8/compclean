import AppKit
import CleanerCore
import SwiftUI

extension Safety {
    var color: Color {
        switch self {
        case .rebuildsItself: .green
        case .leftover: .blue
        case .reviewFirst: .orange
        case .yourFile: .pink
        }
    }

    var symbol: String {
        switch self {
        case .rebuildsItself: "arrow.triangle.2.circlepath"
        case .leftover: "shippingbox"
        case .reviewFirst: "eye"
        case .yourFile: "person.crop.circle"
        }
    }

    var help: String {
        switch self {
        case .rebuildsItself: "The app recreates this automatically. Safe to remove."
        case .leftover: "Belongs to an app that is no longer installed."
        case .reviewFirst: "Probably not needed, but take a quick look first."
        case .yourFile: "Your own file. Only remove it if you're sure."
        }
    }
}

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Label(safety.title, systemImage: safety.symbol)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(safety.color)
            .background(safety.color.opacity(0.14), in: Capsule())
            .help(safety.help)
    }
}

/// One row: what it is, who it belongs to, how safe it is, when it was last used.
/// Expands to show why it can go and exactly where it lives.
struct ReviewRow: View {
    @EnvironmentObject var ai: AIAssistant
    let url: URL
    let size: Int64
    let explanation: Explanation
    @Binding var isSelected: Bool
    var home: String = SafetyPolicy().home
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: $isSelected).toggleStyle(.checkbox).labelsHidden()
                Image(nsImage: NSWorkspace.shared.icon(forFile: explanation.ownerAppPath ?? url.path))
                    .resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(explanation.title).lineLimit(1)
                    HStack(spacing: 8) {
                        SafetyBadge(safety: explanation.safety)
                        if let used = explanation.lastUsed {
                            Text("Last used \(used.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Text(ByteFormat.string(size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                if ai.isUsable && !expanded {
                    Button {
                        withAnimation(.ui) { expanded = true }
                    } label: {
                        Label("Ask", systemImage: "sparkles")
                    }
                    .buttonStyle(.glass).controlSize(.small)
                    .help("Ask the on-device AI about this item")
                }
                Button {
                    withAnimation(.ui) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .help(expanded ? "Hide details" : "What is this?")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explanation.reason).font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(url.path.replacingOccurrences(of: home, with: "~"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.glass).controlSize(.small)
                    }
                    if ai.isUsable {
                        AskPanel(facts: AIFacts.item(url: url, size: size, explanation: explanation, home: home))
                    }
                }
                .padding(.leading, 66)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Grouped, explained list of review items with a floating "Move to Trash" capsule.
struct ReviewList: View {
    let items: [ReviewItem]
    @Binding var selection: Set<String>
    var actionTitle = "Move to Trash"
    var isWorking = false
    var emptyText = "Nothing found."
    let onTrash: () -> Void
    @State private var confirming = false

    private var groups: [(name: String, items: [ReviewItem])] {
        var order: [String] = []
        var map: [String: [ReviewItem]] = [:]
        for item in items {
            if map[item.group] == nil { order.append(item.group) }
            map[item.group, default: []].append(item)
        }
        return order.map { ($0, map[$0]!) }
    }

    private var selectedBytes: Int64 { items.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.size } }
    private var selectedHasOwnFiles: Bool {
        items.contains { selection.contains($0.id) && $0.explanation.safety == .yourFile }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "checkmark.seal")
            } else {
                VStack(spacing: 0) {
                    AIHint().padding(.horizontal, 16).padding(.bottom, 6)
                    List {
                        ForEach(groups, id: \.name) { group in
                            Section {
                                ForEach(group.items) { item in
                                    ReviewRow(url: item.url, size: item.size, explanation: item.explanation,
                                              isSelected: binding(for: item.id))
                                }
                            } header: {
                                groupHeader(group.name, group.items)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .safeAreaPadding(.bottom, 80)
                    .frame(minHeight: 0)
                }
                .overlay(alignment: .bottom) { capsule }
            }
        }
        .confirmationDialog("Move \(selection.count) items to the Trash?", isPresented: $confirming) {
            Button("Move \(ByteFormat.string(selectedBytes)) to Trash", role: .destructive, action: onTrash)
        } message: {
            Text(selectedHasOwnFiles
                 ? "This includes your own files. You can put anything back from History or the Trash."
                 : "You can put anything back from History or the Trash.")
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { selection.contains(id) },
                set: { on in if on { selection.insert(id) } else { selection.remove(id) } })
    }

    private func groupHeader(_ name: String, _ items: [ReviewItem]) -> some View {
        let ids = Set(items.map(\.id))
        let all = ids.isSubset(of: selection)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { all },
                set: { on in if on { selection.formUnion(ids) } else { selection.subtract(ids) } }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            Text(name).fontWeight(.semibold)
            Text(ByteFormat.string(items.reduce(0) { $0 + $1.size })).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            Text(items.count == 1 ? "1 item" : "\(items.count) items").foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.top, 6)
    }

    private var capsule: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(ByteFormat.string(selectedBytes)) selected")
                    .font(.headline.monospacedDigit()).contentTransition(.numericText())
                Text("\(selection.count) of \(items.count) items · goes to the Trash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { confirming = true } label: {
                HStack(spacing: 6) {
                    if isWorking { ProgressView().controlSize(.small) } else { Image(systemName: "trash") }
                    Text(actionTitle)
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .disabled(selection.isEmpty || isWorking)
        }
        .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 16)
        .animation(.ui, value: selection)
    }
}
