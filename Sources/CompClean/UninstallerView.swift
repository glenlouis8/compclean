import AppKit
import CleanerCore
import SwiftUI
import UniformTypeIdentifiers

struct UninstallerView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var sortBySize = true
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 16) {
            appList.frame(width: 290)
                .glassCard(cornerRadius: 24)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(cornerRadius: 24)
        }
        .padding(16)
        .animation(.ui, value: model.chosenApp)
        .animation(.ui, value: model.justUninstalled)
        .task { if model.apps.isEmpty { await model.loadApps() } }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await model.choose(appAt: url) }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).fill(.tint.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6])))
                    .overlay(Label("Drop to inspect", systemImage: "arrow.down.app").font(.title2.bold()).foregroundStyle(.tint))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: App list

    private var shownApps: [AppInfo] {
        let base = search.isEmpty ? model.apps : model.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        guard sortBySize else { return base }
        return base.sorted { (model.appSizes[$0.id] ?? 0) > (model.appSizes[$1.id] ?? 0) }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(model.apps.count) apps", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                Menu {
                    Picker("Sort", selection: $sortBySize) {
                        Text("Largest first").tag(true)
                        Text("By name").tag(false)
                    }
                    .pickerStyle(.inline)
                } label: { Image(systemName: "arrow.up.arrow.down") }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Sort apps")
            }
            .padding(12)

            if model.isLoadingApps {
                ProgressView("Finding apps…").frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shownApps) { app in AppRow(app: app) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let app = model.chosenApp {
            AppDetail(app: app)
        } else if let done = model.justUninstalled {
            UninstallDone(summary: done)
        } else {
            DropZone(message: model.uninstallMessage)
        }
    }
}

struct AppRow: View {
    @EnvironmentObject var model: AppModel
    let app: AppInfo
    @State private var hovering = false

    private var isChosen: Bool { model.chosenApp?.id == app.id }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1).fontWeight(isChosen ? .semibold : .regular)
                if let v = app.version { Text("Version \(v)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            if let size = model.appSizes[app.id] {
                Text(ByteFormat.string(size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isChosen ? Color.accentColor.opacity(0.22) : hovering ? Color.primary.opacity(0.06) : .clear)
        )
        .animation(.ui, value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { Task { await model.choose(app) } }
    }
}

struct DropZone: View {
    let message: String?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .frame(width: 180, height: 140)
                Image(systemName: "app.badge.checkmark").font(.system(size: 52, weight: .light)).foregroundStyle(.secondary)
            }
            Text("Pick an app to uninstall").font(.title2.bold())
            Text(message ?? "Choose one on the left, or drag an app here.\nYou'll see every file it put on your Mac before anything is removed.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

struct UninstallDone: View {
    @EnvironmentObject var model: AppModel
    let summary: UninstallSummary
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: summary.icon).resizable().frame(width: 96, height: 96)
                    .saturation(0).opacity(0.55)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white, .green)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                    .offset(x: 8, y: 8)
            }
            VStack(spacing: 6) {
                Text("\(summary.name) is uninstalled").font(.title2.bold())
                Text("Moved \(summary.count) items (\(ByteFormat.string(summary.bytes))) to the Trash.")
                    .foregroundStyle(.secondary)
                if summary.leftBehind > 0 {
                    Text("\(summary.leftBehind) possible matches were left alone because you didn't tick them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Open Trash") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: model.policy.home + "/.Trash"))
                }
                .buttonStyle(.glass)
                Button("Done") { model.justUninstalled = nil }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            Text("Changed your mind? Drag the app back out of the Trash into Applications.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(0.15)) { appeared = true } }
    }
}

struct AppDetail: View {
    @EnvironmentObject var model: AppModel
    let app: AppInfo
    @State private var confirming = false

    private var appItems: [Leftover] { model.leftovers.filter { $0.match == .app } }
    private var userItems: [Leftover] { model.leftovers.filter { $0.match != .app && !$0.needsAdmin } }
    private var systemItems: [Leftover] { model.leftovers.filter { $0.match != .app && $0.needsAdmin } }
    private var totalBytes: Int64 { model.leftovers.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isFindingLeftovers {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Searching every folder for \(app.name)'s files…").foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    group("The app", symbol: "app", items: appItems)
                    group("Your Library", symbol: "person.crop.circle", items: userItems)
                    group("System Library", symbol: "lock", items: systemItems,
                          note: "Third-party files only. Asks for your password once.")
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .safeAreaPadding(.bottom, 80)
            }
        }
        .overlay(alignment: .bottom) { actionCapsule }
        .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirming) {
            Button("Move \(model.leftoverSelection.count) items to Trash", role: .destructive) {
                Task { await model.uninstallChosen() }
            }
        } message: {
            Text("\(app.name) will be quit first. You can restore anything from the Trash.")
        }
    }

    /// Floating glass capsule with the selection summary and the uninstall action.
    private var actionCapsule: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(ByteFormat.string(model.chosenSelectedBytes)) selected")
                    .font(.headline.monospacedDigit()).contentTransition(.numericText())
                Text(model.uninstallMessage ?? "\(model.leftoverSelection.count) of \(model.leftovers.count) items · goes to the Trash")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Button(role: .destructive) { confirming = true } label: {
                Label("Uninstall", systemImage: "trash").frame(minWidth: 100)
            }
            .buttonStyle(.glassProminent).tint(.red).controlSize(.large)
            .disabled(model.leftoverSelection.isEmpty || model.isFindingLeftovers)
        }
        .padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 16)
        .animation(.ui, value: model.leftoverSelection)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 24, weight: .bold)).tracking(-0.3).lineLimit(1)
                Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: "  ·  "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !model.isFindingLeftovers {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormat.string(totalBytes)).font(.system(.title2, design: .rounded).bold()).monospacedDigit()
                    Text("in \(model.leftovers.count) places").font(.caption).foregroundStyle(.secondary)
                }
                Menu {
                    Button("Recommended") { model.selectLeftovers(.recommended) }
                    Button("Everything") { model.selectLeftovers(.all) }
                    Button("Nothing") { model.selectLeftovers(.none) }
                } label: { Label("Select", systemImage: "checklist") }
                .buttonStyle(.glass)
                .fixedSize()
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private func group(_ title: String, symbol: String, items: [Leftover], note: String? = nil) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { LeftoverRow(item: $0) }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                    Text(title).fontWeight(.semibold)
                    Text(ByteFormat.string(items.reduce(0) { $0 + $1.size })).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                .font(.callout)
                .padding(.top, 6)
            }
        }
    }
}

struct LeftoverRow: View {
    @EnvironmentObject var model: AppModel
    let item: Leftover

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.leftoverSelection.contains(item.id) },
                set: { on in if on { model.leftoverSelection.insert(item.id) } else { model.leftoverSelection.remove(item.id) } }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent).lineLimit(1)
                    MatchBadge(kind: item.match)
                }
                Text(item.url.deletingLastPathComponent().path.replacingOccurrences(of: model.policy.home, with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless).help("Show in Finder")
        }
        .padding(.vertical, 2)
    }
}

struct MatchBadge: View {
    let kind: MatchKind

    var body: some View {
        if kind != .app {
            Text(kind.preselected ? "Sure match" : "Possible match")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .foregroundStyle(kind.preselected ? Color.green : Color.orange)
                .background((kind.preselected ? Color.green : Color.orange).opacity(0.14), in: Capsule())
                .help(kind.label)
        }
    }
}
