import AppKit
import CleanerCore
import SwiftUI

/// The menu bar extra: a standard menu, as Apple's guidelines ask ("a menu, not a popover").
/// Greyed lines are status, the rest are actions. Every item has an icon.
struct MenuBarMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        status("\(ByteFormat.string(model.diskFree)) free on Macintosh HD", "internaldrive")
        if let estimate = model.quickEstimate {
            status(estimate > 0 ? "\(ByteFormat.string(estimate)) of caches ready to clean" : "Caches are already clean",
                   "archivebox")
        }
        if let last = model.lastQuickFreed {
            status("Last clean moved \(ByteFormat.string(last)) to the Trash", "trash")
        }

        Divider()

        Button {
            Task { await model.quickClean(reason: "clean") }
        } label: {
            Label(model.isCleaning ? "Cleaning…" : "Clean Caches Now", systemImage: "sparkles")
        }
        .disabled(model.isCleaning || model.quickEstimate == 0)
        status(autoCleanText, "calendar.badge.clock")

        Divider()

        Section("Go to") {
            Button { open(.cleaner, scan: true) } label: { Label("Scan and Review…", systemImage: "magnifyingglass") }
            Button { open(.diskMap) } label: { Label("Disk Map…", systemImage: "square.grid.3x3.square") }
            Button { open(.uninstaller) } label: { Label("Uninstall an App…", systemImage: "trash.square") }
            Button { open(.history) } label: { Label("History…", systemImage: "clock.arrow.circlepath") }
        }

        Divider()

        Button { open(nil) } label: { Label("Open Suds", systemImage: "macwindow") }
            .keyboardShortcut("o")
        Button { open(.settings) } label: { Label("Settings…", systemImage: "gearshape") }
            .keyboardShortcut(",")

        Divider()

        Button { NSApp.terminate(nil) } label: { Label("Quit Suds", systemImage: "power") }
            .keyboardShortcut("q")
    }

    /// A greyed, non-clickable line with an icon.
    private func status(_ text: String, _ symbol: String) -> some View {
        Button {} label: { Label(text, systemImage: symbol) }.disabled(true)
    }

    private var autoCleanText: String {
        guard model.schedule != .off else { return "Automatic cleaning is off" }
        guard let next = model.nextAutoRun, next > Date() else { return "Automatic cleaning: \(model.schedule.title.lowercased())" }
        return "Next automatic clean \(next.formatted(.relative(presentation: .named)))"
    }

    private func open(_ pane: Pane?, scan: Bool = false) {
        if let pane { model.pane = pane }
        openWindow(id: "main")
        NSApp.activate()
        if scan { Task { await model.scan() } }
    }
}

/// The icon in the menu bar: sparkles, optionally with free space beside it and a dot
/// when there's a lot to clean. Template images so macOS tints them like every other item.
struct MenuBarLabel: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("menuBarShowsFree") private var showsFree = false
    @AppStorage("menuBarShowsDot") private var showsDot = true

    static let dotThreshold: Int64 = 1_000_000_000

    private var hasLots: Bool { showsDot && (model.quickEstimate ?? 0) >= Self.dotThreshold }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.icon(withDot: hasLots))
            if showsFree { Text(Self.short(model.diskFree)) }
        }
        .help(hasLots ? "Over 1 GB of caches ready to clean" : "Suds")
    }

    /// "327 GB" — no decimals, so it stays narrow in the menu bar.
    static func short(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = bytes >= 1_000_000_000_000 ? [.useTB] : [.useGB]
        f.isAdaptive = bytes >= 1_000_000_000_000
        return f.string(fromByteCount: bytes)
    }

    static func icon(withDot dot: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Suds")?
            .withSymbolConfiguration(config) else { return NSImage() }
        guard dot else { symbol.isTemplate = true; return symbol }
        let size = NSSize(width: symbol.size.width + 3, height: symbol.size.height)
        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: 0, width: symbol.size.width, height: symbol.size.height))
            let d: CGFloat = 5.5
            NSBezierPath(ovalIn: NSRect(x: size.width - d, y: size.height - d, width: d, height: d)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
