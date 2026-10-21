import AppKit
import CleanerCore
import SwiftUI

/// Cleaner: a glowing ring of what can go, a slim disk bar, then the categories as a grouped list.
struct CleanerView: View {
    @EnvironmentObject var model: AppModel
    @State private var reviewing: CleanCategory?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CleanerHero()
                if model.isSummarizing || model.scanSummary != nil {
                    AISummaryCard(text: model.scanSummary)
                        .padding(16).card(cornerRadius: 16)
                        .transition(.blurReplace)
                }
                if let freed = model.justFreed {
                    SuccessBanner(bytes: freed) { withAnimation(.ui) { model.justFreed = nil } }
                        .padding(16).card(cornerRadius: 16, outline: .green.opacity(0.5))
                        .transition(.blurReplace)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.hasScanned ? "Found on your Mac" : "What to look for")
                        .font(.headline).padding(.horizontal, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 400), spacing: 14)], spacing: 14) {
                        ForEach(CleanCategory.allCases) { category in
                            CategoryCard(category: category) { reviewing = category }
                        }
                    }
                }
                ProtectedNote().padding(.horizontal, 4)
            }
            .padding(24)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .animation(.ui, value: model.justFreed)
            .animation(.ui, value: model.scanSummary)
        }
        .sheet(item: $reviewing) {
            ReviewSheet(category: $0).environmentObject(model).environmentObject(model.ai)
        }
    }
}

// MARK: - Hero

struct CleanerHero: View {
    @EnvironmentObject var model: AppModel

    private var used: Int64 { max(0, model.diskTotal - model.diskFree) }
    private var found: [(category: CleanCategory, bytes: Int64)] {
        CleanCategory.allCases.map { ($0, model.bytes(in: $0)) }.filter { $0.bytes > 0 }
            .sorted { $0.bytes > $1.bytes }
    }
    private var scanProgress: Double? {
        guard model.isScanning else { return nil }
        return Double(model.scannedCategories.count) / Double(max(1, model.enabledCategories.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 36) {
                ring.frame(width: 200, height: 200)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text(subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !found.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(found, id: \.category) { f in
                                LegendRow(colors: f.category.gradient, label: f.category.title, bytes: f.bytes)
                            }
                        }
                        .frame(maxWidth: 300)
                    }
                    actions
                }
                Spacer(minLength: 0)
            }
            diskLine
        }
        .padding(26)
        .background(
            LinearGradient(colors: [Palette.brand[0].opacity(0.10), Palette.brand[1].opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var ring: some View {
        JunkRing(slices: found.map { .init(id: $0.category.rawValue, bytes: $0.bytes, colors: $0.category.gradient) },
                 diskUsedFraction: model.diskTotal > 0 ? Double(used) / Double(model.diskTotal) : 0,
                 progress: scanProgress) {
            VStack(spacing: 2) {
                if model.isScanning {
                    Text("\(Int((scanProgress ?? 0) * 100))%")
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(model.scanningCategory?.title ?? "Scanning").font(.caption).foregroundStyle(.secondary)
                } else if !found.isEmpty {
                    Text(ByteFormat.string(model.foundBytes))
                        .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("can go").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(ByteFormat.string(model.diskFree))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("free").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var headline: String {
        if model.isScanning { return "Looking for junk…" }
        if model.isCleaning { return "Cleaning…" }
        if model.hasScanned { return model.foundBytes > 0 ? "Ready to clean" : "All tidy" }
        return "Let's tidy up"
    }

    private var subheadline: String {
        if model.isScanning { return "Only checking folders that are safe to clean." }
        if model.hasScanned {
            return model.foundBytes > 0
                ? "\(ByteFormat.string(model.selectedBytes)) selected. Review anything before it goes to the Trash."
                : "Nothing worth removing right now."
        }
        return "Scan to find caches, old logs and developer junk. Nothing is removed until you choose."
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if model.hasScanned && model.foundBytes > 0 {
                Button { Task { await model.cleanSelected() } } label: {
                    Label(model.isCleaning ? "Cleaning…" : "Clean \(ByteFormat.string(model.selectedBytes))",
                          systemImage: "sparkles").frame(minWidth: 140)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.selected.isEmpty || model.isCleaning || model.isScanning)
                Button { Task { await model.scan() } } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glass)
                    .disabled(model.isScanning || model.isCleaning)
            } else {
                Button { Task { await model.scan() } } label: {
                    Label(model.isScanning ? "Scanning…" : (model.hasScanned ? "Scan again" : "Scan my Mac"),
                          systemImage: "magnifyingglass").frame(minWidth: 140)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isScanning || model.isCleaning || model.enabledCategories.isEmpty)
            }
        }
        .controlSize(.extraLarge)
    }

    /// Slim disk bar under the hero: how full Macintosh HD is.
    private var diskLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Macintosh HD", systemImage: "internaldrive").font(.callout.weight(.medium))
                Spacer()
                Text("\(ByteFormat.string(model.diskFree)) free of \(ByteFormat.string(model.diskTotal))")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let f = model.diskTotal > 0 ? Double(used) / Double(model.diskTotal) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: Palette.disk, startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * f)
                }
            }
            .frame(height: 6)
        }
    }
}

struct LegendRow: View {
    let colors: [Color]
    let label: String
    let bytes: Int64

    var body: some View {
        HStack(spacing: 9) {
            Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 18, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(ByteFormat.string(bytes)).monospacedDigit().fontWeight(.semibold)
        }
        .font(.callout)
    }
}

// MARK: - Category card

/// One kind of junk: gradient icon, what it is, how much was found, and a checkmark to include it.
struct CategoryCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    let category: CleanCategory
    let onReview: () -> Void
    @State private var hovering = false

    private var isScanned: Bool { model.scannedCategories.contains(category) }
    private var isEnabled: Bool { model.enabledCategories.contains(category) }
    private var count: Int { model.findings(in: category).count }
    private var isOn: Bool { isScanned ? model.selectedBytes(in: category) > 0 : isEnabled }
    private var canToggle: Bool { !model.isScanning && !(isScanned && count == 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                IconTile(symbol: category.symbol, gradient: category.gradient, size: 38)
                Spacer()
                check
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).font(.headline)
                Text(category.detail).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            footer.frame(height: 28)
        }
        .padding(16)
        .background(category.color.opacity(isOn ? 0.09 : 0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(isOn ? category.color.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: isOn ? 1.5 : 1))
        .scaleEffect(hovering && canToggle ? 1.012 : 1)
        .contentShape(.rect(cornerRadius: 18))
        .onHover { h in withAnimation(.ui) { hovering = h } }
        .onTapGesture { if canToggle { withAnimation(.ui) { toggle() } } }
        .animation(.ui, value: isOn)
    }

    /// Filled circle with a checkmark when included, an empty ring when not.
    private var check: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.5)
            if isOn {
                Circle().fill(LinearGradient(colors: category.gradient, startPoint: .top, endPoint: .bottom))
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .opacity(canToggle ? 1 : 0.4)
        .help(isOn ? "Included. Click the card to leave it out." : "Not included. Click the card to include it.")
    }

    @ViewBuilder
    private var footer: some View {
        if model.scanningCategory == category {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Scanning…").foregroundStyle(.secondary) }
        } else if isScanned {
            HStack {
                if count > 0 {
                    Text(ByteFormat.string(model.bytes(in: category)))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(category.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(category.color.mix(with: scheme == .dark ? .white : .black, by: scheme == .dark ? 0.25 : 0.3))
                    Text(count == 1 ? "1 item" : "\(count) items").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Review…", action: onReview).buttonStyle(.link)
                } else {
                    Label("Nothing found", systemImage: "checkmark.seal").font(.callout).foregroundStyle(.secondary)
                }
            }
        } else {
            Label(category.autoSafe ? "Safe to auto clean" : "You review first",
                  systemImage: category.autoSafe ? "checkmark.shield" : "eye")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func toggle() {
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
            AIHint().padding(.horizontal, 20).padding(.bottom, 6)
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

/// The on-device model's plain summary of a scan. Nil text means it's still being written.
struct AISummaryCard: View {
    let text: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: text == nil)
            VStack(alignment: .leading, spacing: 4) {
                if let text {
                    Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else {
                    Text("Writing a summary…").foregroundStyle(.secondary)
                }
                Text("AI summary, written on this Mac. Only the items you tick get cleaned.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

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
        .padding(.vertical, 4)
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

#if DEBUG
#Preview("Cleaner · scanned") {
    CleanerView().previewEnvironment()
}

#Preview("Cleaner · full page") {
    CleanerView().previewEnvironment(width: 720, height: 1250)
}

#Preview("Cleaner · before scan") {
    CleanerView().previewEnvironment(PreviewData.model(scanned: false))
}
#endif
