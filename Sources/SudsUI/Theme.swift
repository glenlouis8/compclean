import AppKit
import CleanerCore
import SwiftUI

enum LeftoverSelection { case recommended, all, none }

/// Light, dark, or follow the Mac. Applied app-wide, menus and sheets included.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match Mac"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    @MainActor static func apply(_ raw: String) {
        NSApp.appearance = (AppAppearance(rawValue: raw) ?? .system).nsAppearance
    }
}

struct UninstallSummary: Equatable {
    let name: String
    let icon: NSImage
    let bytes: Int64
    let count: Int
    /// Items found but not removed (unticked, or skipped).
    let leftBehind: Int
}

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The app's palette: a two-tone gradient per kind of junk, and a brand gradient.
enum Palette {
    static let brand = [Color(hex: 0x38BDF8), Color(hex: 0x6366F1)]       // sky → indigo
    static let disk = [Color(hex: 0x60A5FA), Color(hex: 0xA78BFA)]        // used space on the ring
}

extension CleanCategory {
    /// One hue per category, light to deep, so a single slice never reads as two categories.
    var gradient: [Color] {
        switch self {
        case .userCaches: [Color(hex: 0x7DB4FF), Color(hex: 0x3B82F6)]    // blue
        case .browserCaches: [Color(hex: 0x5EEAD4), Color(hex: 0x14B8A6)] // teal
        case .oldLogs: [Color(hex: 0xFDE68A), Color(hex: 0xF59E0B)]       // amber
        case .devCaches: [Color(hex: 0xC4B5FD), Color(hex: 0x8B5CF6)]     // violet
        case .oldDownloads: [Color(hex: 0xFDA4AF), Color(hex: 0xF43F5E)]  // rose
        }
    }

    var color: Color { gradient[1] }
}

extension Animation {
    /// Critically damped default for UI state changes.
    static let ui = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// A little bounce, for moments of success.
    static let pop = Animation.spring(response: 0.4, dampingFraction: 0.7)
}

// MARK: - Surfaces

extension View {
    /// A content card: a standard, quiet surface (Apple's guidelines keep Liquid Glass off content).
    /// `outline` marks a selected or highlighted card with a colored border; the fill stays neutral.
    func card(cornerRadius: CGFloat = 14, outline: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Color.primary.opacity(0.045), in: shape)
            .overlay(shape.strokeBorder(outline ?? Color.primary.opacity(0.08), lineWidth: outline == nil ? 1 : 1.5))
    }
}

/// Round glass button holding just an icon, for secondary actions.
struct GlassIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help(help)
    }
}

/// Rounded tinted square holding an SF Symbol, used for categories and headers.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 36

    init(symbol: String, color: Color, size: CGFloat = 36) {
        self.symbol = symbol
        self.colors = [color.mix(with: .white, by: 0.15), color]
        self.size = size
    }

    init(symbol: String, gradient: [Color], size: CGFloat = 36) {
        self.symbol = symbol
        self.colors = gradient
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .shadow(color: (colors.last ?? .clear).opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

// MARK: - Junk ring

/// Fitness-style ring. With slices, each kind of junk gets a glowing gradient arc sized by its share.
/// Without slices, it shows how full the disk is. `progress` draws a thin inner ring while scanning.
struct JunkRing<Center: View>: View {
    struct Slice: Identifiable {
        let id: String
        let bytes: Int64
        let colors: [Color]
    }

    var slices: [Slice]
    var diskUsedFraction: Double
    var progress: Double?
    var lineWidth: CGFloat = 22
    @ViewBuilder var center: Center

    /// Slice positions. Every slice gets at least a small visible share, and gaps leave room
    /// for the round caps (about one line width of the circumference) so slices don't merge.
    private var arcs: [(slice: Slice, start: Double, end: Double)] {
        let total = Double(slices.reduce(0) { $0 + $1.bytes })
        guard total > 0 else { return [] }
        let gap = slices.count > 1 ? 0.06 : 0
        // Tiny items show as a short dot, not a slice that overstates them.
        let minShare = 0.008
        let raw = slices.map { max(minShare, Double($0.bytes) / total) }
        let scale = (1 - gap * Double(slices.count)) / raw.reduce(0, +)
        var start = gap / 2
        return zip(slices, raw).map { s, r in
            let len = r * scale
            defer { start += len + gap }
            return (s, start, start + max(0.001, len))
        }
    }

    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
                if arcs.isEmpty {
                    arc(0, max(0.004, diskUsedFraction), colors: Palette.disk)
                } else {
                    ForEach(arcs, id: \.slice.id) { a in arc(a.start, a.end, colors: a.slice.colors) }
                }
                if let progress {
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .padding(lineWidth + 6)
                }
            }
            .rotationEffect(.degrees(-90))
            center
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: slices.map(\.bytes))
        .animation(.ui, value: diskUsedFraction)
        .animation(.ui, value: progress)
    }

    private func arc(_ from: Double, _ to: Double, colors: [Color]) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(
                AngularGradient(colors: colors, center: .center,
                                startAngle: .degrees(from * 360), endAngle: .degrees(to * 360)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .shadow(color: (colors.last ?? .clear).opacity(0.55), radius: 10)
    }
}

/// A gentle color wash at the top of a screen, in that screen's color. No blur, so it's cheap to draw.
struct ScreenWash: View {
    var colors: [Color]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [colors[0].opacity(0.16), (colors.last ?? colors[0]).opacity(0.05), .clear],
                           startPoint: .topLeading, endPoint: UnitPoint(x: 0.8, y: 0.6))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Disk visuals

/// Thin capsule version of the disk bar, used in the sidebar.
struct DiskBar: View {
    let total: Int64
    let free: Int64
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let usedW = total > 0 ? geo.size.width * CGFloat(max(0, total - free)) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [.teal, .blue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: usedW)
            }
        }
        .frame(height: height)
        .animation(.ui, value: free)
    }
}
