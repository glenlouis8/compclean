import AppKit
import CleanerCore
import SwiftUI

struct CleanerView: View {
    @EnvironmentObject var model: AppModel
    @State private var reviewing: CleanCategory?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                if let freed = model.justFreed {
                    SuccessBanner(bytes: freed) { withAnimation(.ui) { model.justFreed = nil } }
                        .transition(.blurReplace)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(model.hasScanned ? "Found on your Mac" : "What to look for")
                        .font(.title3.weight(.semibold))
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(CleanCategory.allCases) { category in
                            CategoryCard(category: category) { reviewing = category }
                        }
                    }
                }
                ProtectedNote()
            }
            .padding(28)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .animation(.ui, value: model.justFreed)
        }
        .sheet(item: $reviewing) { ReviewSheet(category: $0) }
    }

    // MARK: Hero

    private var scanProgress: Double? {
        guard model.isScanning else { return nil }
        return Double(model.scannedCategories.count) / Double(max(1, model.enabledCategories.count))
    }

    private var hero: some View {
        HStack(spacing: 40) {
            DiskRing(total: model.diskTotal, free: model.diskFree, reclaimable: model.foundBytes,
                     progress: scanProgress, lineWidth: 20) {
                VStack(spacing: 2) {
                    if model.isScanning {
                        Text("\(Int((scanProgress ?? 0) * 100))%")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text(model.scanningCategory?.title ?? "Scanning")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(ByteFormat.string(model.diskFree))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("available").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 210, height: 210)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.system(size: 26, weight: .bold)).tracking(-0.3)
                        .contentTransition(.opacity)
                    Text(subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    StatLine(color: .primary.opacity(0.5), label: "Used",
                             value: ByteFormat.string(max(0, model.diskTotal - model.diskFree)))
                    StatLine(color: .teal, label: "Can clean", value: ByteFormat.string(model.foundBytes))
                    StatLine(color: .primary.opacity(0.12), label: "Available", value: ByteFormat.string(model.diskFree))
                }
                .frame(maxWidth: 320)
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(30)
        .glassCard(cornerRadius: 30)
    }

    private var headline: String {
        if model.isScanning { return "Looking for junk…" }
        if model.isCleaning { return "Cleaning…" }
        if model.hasScanned { return model.foundBytes > 0 ? "\(ByteFormat.string(model.foundBytes)) can go" : "All tidy" }
        return "Macintosh HD"
    }

    private var subheadline: String {
        if model.isScanning { return "Checking only the folders that are safe to clean." }
        if model.hasScanned {
            return model.foundBytes > 0
                ? "\(ByteFormat.string(model.selectedBytes)) selected. Review any card before cleaning."
                : "Nothing worth removing right now."
        }
        return "\(ByteFormat.string(model.diskFree)) free of \(ByteFormat.string(model.diskTotal)). Scan to see what can be cleared."
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if model.hasScanned && model.foundBytes > 0 {
                Button {
                    Task { await model.cleanSelected() }
                } label: {
                    Label(model.isCleaning ? "Cleaning…" : "Clean \(ByteFormat.string(model.selectedBytes))",
                          systemImage: "sparkles")
                        .frame(minWidth: 150)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.selected.isEmpty || model.isCleaning || model.isScanning)

                Button {
                    Task { await model.scan() }
                } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .buttonStyle(.glass)
                .disabled(model.isScanning || model.isCleaning)
            } else {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label(model.isScanning ? "Scanning…" : (model.hasScanned ? "Scan again" : "Scan my Mac"),
                          systemImage: "magnifyingglass")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isScanning || model.isCleaning || model.enabledCategories.isEmpty)
            }
        }
        .controlSize(.extraLarge)
    }
}

// MARK: - Category card

struct CategoryCard: View {
    @EnvironmentObject var model: AppModel
    let category: CleanCategory
    let onReview: () -> Void
    @State private var hovering = false

    private var isScanningThis: Bool { model.scanningCategory == category }
    private var isScanned: Bool { model.scannedCategories.contains(category) }
    private var isEnabled: Bool { model.enabledCategories.contains(category) }
    private var count: Int { model.findings(in: category).count }
    private var isOn: Bool { isScanned ? model.selectedBytes(in: category) > 0 : isEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                IconTile(symbol: category.symbol, color: category.color, size: 40)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? category.color : Color.secondary.opacity(0.4))
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title).font(.headline)
                Text(category.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            footer.frame(height: 30)
        }
        .padding(18)
        .glassCard(cornerRadius: 22, tint: isOn ? category.color : nil)
        .opacity(model.hasScanned && !isEnabled ? 0.65 : 1)
        .scaleEffect(hovering ? 1.015 : 1)
        .contentShape(.rect(cornerRadius: 22))
        .onHover { h in withAnimation(.ui) { hovering = h } }
        .onTapGesture { withAnimation(.ui) { toggle() } }
        .animation(.ui, value: isOn)
        .animation(.ui, value: isScanned)
    }

    @ViewBuilder
    private var footer: some View {
        if isScanningThis {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning…").foregroundStyle(.secondary)
            }
        } else if isScanned {
            HStack(alignment: .firstTextBaseline) {
                Text(ByteFormat.string(model.bytes(in: category)))
                    .font(.system(.title3, design: .rounded).bold()).monospacedDigit()
                    .contentTransition(.numericText())
                Text(count == 1 ? "1 item" : "\(count) items").font(.callout).foregroundStyle(.secondary)
                Spacer()
                if count > 0 {
                    Button("Review", action: onReview).buttonStyle(.glass).controlSize(.small)
                }
            }
        } else if model.hasScanned && !isEnabled {
            HStack {
                Text("Not scanned").foregroundStyle(.secondary)
                Spacer()
                Button("Scan") { Task { await model.scanOne(category) } }
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(model.isScanning)
            }
        } else {
            Label(category.autoSafe ? "Safe to auto clean" : "You review first",
                  systemImage: category.autoSafe ? "checkmark.shield" : "eye")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func toggle() {
        guard !model.isScanning else { return }
        if isScanned {
            model.setCategorySelected(category, !isOn)
        } else if model.hasScanned {
            Task { await model.scanOne(category) }
        } else if isEnabled {
            model.enabledCategories.remove(category)
        } else {
            model.enabledCategories.insert(category)
        }
    }
}

// MARK: - Review sheet

struct ReviewSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let category: CleanCategory

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: category.symbol, color: category.color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.title3.bold())
                    Text("\(ByteFormat.string(model.selectedBytes(in: category))) of \(ByteFormat.string(model.bytes(in: category))) selected")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        Button("All") { model.setCategorySelected(category, true) }.buttonStyle(.glass)
                        Button("None") { model.setCategorySelected(category, false) }.buttonStyle(.glass)
                    }
                }
            }
            .padding(20)
            List(model.findings(in: category)) { FindingRow(item: $0) }
                .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 660, height: 540)
    }
}

struct FindingRow: View {
    @EnvironmentObject var model: AppModel
    let item: Finding

    var body: some View {
        ReviewRow(
            url: item.url, size: item.size,
            explanation: model.explanations[item.id]
                ?? Explanation(title: item.displayName, safety: item.category.autoSafe ? .rebuildsItself : .yourFile,
                               reason: item.category.detail),
            isSelected: Binding(
                get: { model.selected.contains(item.id) },
                set: { on in if on { model.selected.insert(item.id) } else { model.selected.remove(item.id) } }
            ),
            home: model.policy.home
        )
    }
}

// MARK: - Small pieces

struct SuccessBanner: View {
    @EnvironmentObject var model: AppModel
    let bytes: Int64
    let onClose: () -> Void
    @State private var bounce = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(.white, .green)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 2) {
                Text("Moved \(ByteFormat.string(bytes)) to the Trash").font(.headline)
                Text("The space comes back when you empty the Trash. Changed your mind? Put it back from History.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Trash") {
                NSWorkspace.shared.open(URL(fileURLWithPath: model.policy.home + "/.Trash"))
            }
            .buttonStyle(.glass)
            GlassIconButton(symbol: "xmark", help: "Dismiss", size: 28, action: onClose)
        }
        .padding(18)
        .glassCard(cornerRadius: 22, tint: .green)
        .onAppear { bounce.toggle() }
    }
}

struct ProtectedNote: View {
    var body: some View {
        Label {
            Text("Never touched: macOS and Apple files, cookies and logins, browser history, keychains, Mail, Messages, Photos and iCloud.")
                .font(.callout).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "lock.shield.fill").foregroundStyle(.green)
        }
    }
}
