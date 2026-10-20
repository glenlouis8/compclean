import AppKit
import CleanerCore
import SwiftUI

@main
struct CompCleanApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("CompClean", id: "main") {
            MainView()
                .environmentObject(model)
                .environmentObject(model.history)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case cleaner = "Cleaner"
    case devJunk = "Developer junk"
    case leftovers = "Leftovers"
    case bigFiles = "Big files"
    case duplicates = "Duplicates"
    case diskMap = "Disk map"
    case uninstaller = "Uninstaller"
    case unusedApps = "Unused apps"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .cleaner: "sparkles"
        case .devJunk: "hammer"
        case .leftovers: "shippingbox"
        case .bigFiles: "doc.zipper"
        case .duplicates: "square.on.square"
        case .diskMap: "square.grid.3x3.square"
        case .uninstaller: "trash.square"
        case .unusedApps: "moon.zzz"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }

    /// Colors of the soft background glow behind each screen.
    var ambient: [Color] {
        switch self {
        case .cleaner: [.teal, .blue, .purple]
        case .devJunk: [.purple, .indigo, .blue]
        case .leftovers: [.blue, .indigo, .teal]
        case .bigFiles: [.pink, .orange, .purple]
        case .duplicates: [.orange, .pink, .yellow]
        case .diskMap: [.cyan, .blue, .purple]
        case .uninstaller: [.purple, .pink, .blue]
        case .unusedApps: [.indigo, .purple, .pink]
        case .history: [.green, .teal, .blue]
        case .settings: [.blue, .indigo, .teal]
        }
    }

    /// Sidebar sections, in order.
    static let sections: [(title: String?, panes: [Pane])] = [
        ("Clean", [.cleaner, .devJunk]),
        ("Find", [.diskMap, .leftovers, .bigFiles, .duplicates]),
        ("Apps", [.uninstaller, .unusedApps]),
        (nil, [.history, .settings]),
    ]
}

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            // Plain stacking: glass inside safeAreaInset gets hidden by macOS's scroll edge effect.
            VStack(spacing: 0) {
                List(selection: $model.pane) {
                    ForEach(Pane.sections, id: \.panes) { section in
                        Section {
                            ForEach(section.panes) { p in
                                Label(p.rawValue, systemImage: p.symbol).tag(p).padding(.vertical, 2)
                            }
                        } header: {
                            if let title = section.title { Text(title) }
                        }
                    }
                }
                .frame(minHeight: 0)
                .probe("sidebar list")
                SidebarFooter().probe("sidebar footer")
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 250)
        } detail: {
            VStack(spacing: 0) {
                if !model.hasFullDiskAccess {
                    PermissionBanner().padding([.horizontal, .top], 16).probe("permission banner")
                }
                // minHeight 0: screens scroll inside the window instead of growing it to fit long lists.
                detailContent
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .probe("detail content")
            }
            // One background behind the banner and the screen, so it can't be painted over the banner.
            .background(AmbientBackground(colors: (model.pane ?? .cleaner).ambient))
        }
        // Show in the Dock only while this window is open; the menu bar icon stays either way.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermission()
            model.refreshDisk()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.pane ?? .cleaner {
        case .cleaner: CleanerView()
        case .uninstaller: UninstallerView()
        case .devJunk: DevJunkView()
        case .leftovers:
            FinderScreen(store: model.leftoversStore, title: "Leftovers",
                         subtitle: "Files that apps you already deleted left in your Library: settings, caches, background tasks.",
                         symbol: "shippingbox", color: .blue,
                         emptyText: "No leftovers from deleted apps.")
        case .bigFiles: BigFilesView()
        case .duplicates: DuplicatesView()
        case .diskMap: DiskMapView(store: model.diskMap)
        case .unusedApps: UnusedAppsView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

/// Disk space and total moved to the Trash, under the sidebar list.
struct SidebarFooter: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Macintosh HD").font(.caption.weight(.medium))
                Spacer()
                Text("\(ByteFormat.string(model.diskFree)) free").font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            DiskBar(total: model.diskTotal, free: model.diskFree, height: 6)
            HStack(spacing: 8) {
                Image(systemName: "trash").foregroundStyle(.secondary).font(.caption)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Moved to Trash").font(.caption).foregroundStyle(.secondary)
                    Text(ByteFormat.string(Int64(model.totalFreed))).font(.callout.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            .help("Space comes back when you empty the Trash.")
        }
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(12)
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "lock.shield.fill", color: .orange, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Turn on Full Disk Access").font(.headline)
                Text("So CompClean can see every cache and leftover. Switch it on for CompClean, then come back.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Recheck") { model.refreshPermission() }.buttonStyle(.glass)
            Button("Open Settings") { model.openFullDiskAccessSettings() }.buttonStyle(.glassProminent).tint(.orange)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        // Plain tint, not glass: glass with nothing drawn behind it renders invisible here.
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.orange.opacity(0.35)))
    }
}
