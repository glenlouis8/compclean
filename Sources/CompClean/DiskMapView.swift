import AppKit
import CleanerCore
import SwiftUI

/// Read-only treemap of the home folder. Click to zoom in, breadcrumb to zoom out.
@MainActor
final class DiskMapStore: ObservableObject {
    @Published var root: DiskNode?
    @Published var stack: [DiskNode] = []
    @Published var isMapping = false
    @Published var counted: Int64 = 0

    let home: String

    init(home: String) { self.home = home }

    var current: DiskNode? { stack.last ?? root }

    func map() async {
        guard !isMapping else { return }
        isMapping = true
        counted = 0
        let url = URL(fileURLWithPath: home)
        let report: @Sendable (Int64) -> Void = { [weak self] bytes in
            Task { @MainActor in self?.counted = bytes }
        }
        let node = await Task.detached { DiskMapper().map(url, progress: report) }.value
        root = node
        stack = []
        isMapping = false
    }

    func open(_ node: DiskNode) {
        guard node.isFolder, !node.children.isEmpty else { return }
        stack.append(node)
    }

    func pop(to index: Int?) {
        if let index { stack = Array(stack.prefix(index + 1)) } else { stack = [] }
    }
}

struct DiskMapView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: DiskMapStore
    @State private var hovered: DiskNode?

    var body: some View {
        VStack(spacing: 12) {
            header
            if let current = store.current {
                breadcrumb
                TreemapView(node: current, hovered: $hovered) { store.open($0) }
                    .padding(.horizontal, 16)
                infoBar(hovered ?? current, parent: current)
                    .padding([.horizontal, .bottom], 16)
            } else if store.isMapping {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Measuring your home folder… \(ByteFormat.string(store.counted)) so far")
                        .monospacedDigit().foregroundStyle(.secondary).contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("See where your space goes", systemImage: "square.grid.3x3.square")
                } description: {
                    Text("A map of everything in your home folder, sized by how much space it takes. It only looks; nothing is changed from here.")
                } actions: {
                    Button("Map my home folder") { Task { await store.map() } }.buttonStyle(.glassProminent).controlSize(.large)
                }
            }
        }
    }

    private var header: some View {
        let used = max(0, model.diskTotal - model.diskFree)
        let homeSize = store.root?.size ?? 0
        return HStack(spacing: 14) {
            IconTile(symbol: "square.grid.3x3.square", color: .cyan, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Disk map").font(.system(size: 24, weight: .bold)).tracking(-0.3)
                Text(store.root == nil
                     ? "\(ByteFormat.string(used)) used on Macintosh HD."
                     : "\(ByteFormat.string(used)) used: \(ByteFormat.string(homeSize)) in your home folder, \(ByteFormat.string(max(0, used - homeSize))) in macOS, apps and other users.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if store.root != nil {
                Button {
                    Task { await store.map() }
                } label: {
                    if store.isMapping {
                        Label("\(ByteFormat.string(store.counted))", systemImage: "hourglass").monospacedDigit()
                    } else {
                        Label("Map again", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.glass).disabled(store.isMapping)
            }
        }
        .padding(22)
        .glassCard(cornerRadius: 24)
        .padding([.horizontal, .top], 16)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    crumb("Home", size: store.root?.size ?? 0) { store.pop(to: nil) }
                    ForEach(Array(store.stack.enumerated()), id: \.element.id) { i, node in
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        crumb(node.name, size: node.size) { store.pop(to: i) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func crumb(_ title: String, size: Int64, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.ui) { action() } }) {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Text(ByteFormat.string(size)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func infoBar(_ node: DiskNode, parent: DiskNode) -> some View {
        let share = parent.size > 0 ? Double(node.size) / Double(parent.size) : 0
        return HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path)).resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(node.name).font(.headline).lineLimit(1)
                    Text(ByteFormat.string(node.size)).monospacedDigit()
                    if node.id != parent.id {
                        Text(share.formatted(.percent.precision(.fractionLength(0))) + " of \(parent.name)")
                            .foregroundStyle(.secondary)
                    }
                }
                Text(node.path.replacingOccurrences(of: model.policy.home, with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let (label, pane) = suggestion(for: node) {
                Button(label) { model.pane = pane }.buttonStyle(.glass)
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
                .buttonStyle(.glass)
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    /// Points at the screen that can actually clean this part of the disk.
    private func suggestion(for node: DiskNode) -> (String, Pane)? {
        let p = node.path
        let home = model.policy.home
        if p.hasPrefix(home + "/Library/Caches") || p.hasPrefix(home + "/Library/Logs") || p.hasPrefix(home + "/.npm") {
            return ("Clean caches", .cleaner)
        }
        if model.devRoots.contains(where: { p == $0.path || p.hasPrefix($0.path + "/") }) {
            return ("Find developer junk", .devJunk)
        }
        if p.hasPrefix(home + "/Library/Application Support") || p.hasPrefix(home + "/Library/Containers") {
            return ("Find leftovers", .leftovers)
        }
        if p.hasPrefix(home + "/Applications") { return ("Unused apps", .unusedApps) }
        for folder in ["Downloads", "Movies", "Documents", "Desktop", "Music", "Pictures"] where p.hasPrefix(home + "/" + folder) {
            return ("Find big files", .bigFiles)
        }
        return nil
    }
}

/// Tiles sized by bytes. The biggest 60 get their own tile; the rest share one "Smaller items" tile.
struct TreemapView: View {
    let node: DiskNode
    @Binding var hovered: DiskNode?
    let onOpen: (DiskNode) -> Void

    static let palette: [Color] = [.blue, .teal, .purple, .pink, .orange, .indigo, .green, .cyan, .mint, .yellow, .red, .brown]

    private var tiles: [DiskNode] {
        let top = Array(node.children.prefix(60))
        let rest = node.children.dropFirst(60)
        guard !rest.isEmpty else { return top }
        let size = rest.reduce(0) { $0 + $1.size }
        return top + [DiskNode(path: node.path + "/…", name: "\(rest.count) smaller items", size: size, isFolder: false)]
    }

    var body: some View {
        GeometryReader { geo in
            let items = tiles
            let rects = Treemap.layout(items.map { Double($0.size) },
                                       in: .init(x: 0, y: 0, w: geo.size.width, h: geo.size.height))
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, child in
                    let r = rects[i]
                    Tile(node: child, color: Self.palette[i % Self.palette.count],
                         isHovered: hovered?.id == child.id, width: r.w, height: r.h)
                        .frame(width: max(0, r.w - 3), height: max(0, r.h - 3))
                        .offset(x: r.x, y: r.y)
                        .onHover { inside in
                            if inside { hovered = child } else if hovered?.id == child.id { hovered = nil }
                        }
                        .onTapGesture { withAnimation(.ui) { onOpen(child) } }
                }
            }
            .id(node.id)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .animation(.ui, value: node.id)
    }
}

private struct Tile: View {
    let node: DiskNode
    let color: Color
    let isHovered: Bool
    let width: Double
    let height: Double

    private var canOpen: Bool { node.isFolder && !node.children.isEmpty }

    var body: some View {
        RoundedRectangle(cornerRadius: min(10, min(width, height) / 4), style: .continuous)
            .fill(color.gradient.opacity(isHovered ? 0.95 : 0.75))
            .overlay(alignment: .topLeading) {
                if width > 70 && height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(ByteFormat.string(node.size)).font(.caption2.monospacedDigit()).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(7)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: min(10, min(width, height) / 4), style: .continuous)
                    .strokeBorder(.white.opacity(isHovered ? 0.7 : 0.15), lineWidth: isHovered ? 2 : 1)
            }
            .contentShape(.rect)
            .help(canOpen ? "\(node.name) · click to look inside" : node.name)
            .animation(.ui, value: isHovered)
    }
}
