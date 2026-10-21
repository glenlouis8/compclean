import AppKit
import CleanerCore
import SwiftUI

/// The whole app: main window and menu bar extra. The executable target just launches this.
public struct CompCleanScenes: Scene {
    @StateObject private var model = AppModel()
    /// People choose whether CompClean lives in the menu bar (Apple's guidelines).
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    public init() {}

    public var body: some Scene {
        Window("CompClean", id: "main") {
            MainView()
                .environmentObject(model)
                .environmentObject(model.history)
                .environmentObject(model.ai)
                .frame(minWidth: 860, minHeight: 560)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu().environmentObject(model)
        } label: {
            MenuBarLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
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

    /// Colors of the soft wash at the top of each screen.
    var wash: [Color] {
        switch self {
        case .cleaner, .settings: Palette.brand
        case .devJunk: CleanCategory.devCaches.gradient
        case .leftovers, .uninstaller: CleanCategory.userCaches.gradient
        case .bigFiles, .duplicates: CleanCategory.oldDownloads.gradient
        case .diskMap: CleanCategory.browserCaches.gradient
        case .unusedApps: [Color(hex: 0x818CF8), Color(hex: 0xC084FC)]
        case .history: [Color(hex: 0x34D399), Color(hex: 0x22D3EE)]
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
    @AppStorage("seenWelcome") private var seenWelcome = false
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("showInMenuBar") private var showInMenuBar = true

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
            // The window title names the screen, like native Mac apps.
            .navigationTitle((model.pane ?? .cleaner).rawValue)
            .background(ScreenWash(colors: (model.pane ?? .cleaner).wash))
        }
        .sheet(isPresented: Binding(get: { !seenWelcome }, set: { if !$0 { seenWelcome = true } })) {
            WelcomeView()
        }
        // Show in the Dock only while this window is open; the menu bar icon stays either way.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            AppAppearance.apply(appearance)
        }
        .onChange(of: appearance) { AppAppearance.apply(appearance) }
        // Leave the Dock only if the menu bar icon is there to get back in.
        .onDisappear { if showInMenuBar { NSApp.setActivationPolicy(.accessory) } }
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
        VStack(alignment: .leading, spacing: 10) {
            stat("internaldrive", "Free on Macintosh HD", model.diskFree)
            DiskBar(total: model.diskTotal, free: model.diskFree, height: 6)
            stat("trash", "Moved to Trash", Int64(model.totalFreed))
                .help("Space comes back when you empty the Trash.")
        }
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(12)
    }

    /// Icon, small label, big number: the same shape for both lines so nothing wraps.
    private func stat(_ symbol: String, _ label: String, _ bytes: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).font(.callout).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(ByteFormat.string(bytes)).font(.callout.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText()).lineLimit(1)
            }
        }
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

#if DEBUG
#Preview("Whole window") {
    MainView().previewEnvironment(width: 960, height: 640)
}
#endif
