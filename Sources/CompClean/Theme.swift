import AppKit
import CleanerCore
import SwiftUI

enum LeftoverSelection { case recommended, all, none }

struct UninstallSummary: Equatable {
    let name: String
    let icon: NSImage
    let bytes: Int64
    let count: Int
    /// Items found but not removed (unticked, or skipped).
    let leftBehind: Int
}

extension CleanCategory {
    var color: Color {
        switch self {
        case .userCaches: .blue
        case .browserCaches: .teal
        case .oldLogs: .indigo
        case .devCaches: .purple
        case .oldDownloads: .pink
        }
    }
}

extension Animation {
    /// Critically damped default for UI state changes.
    static let ui = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// A little bounce, for moments of success.
    static let pop = Animation.spring(response: 0.4, dampingFraction: 0.7)
}

// MARK: - Backgrounds

/// Soft, slow color fields behind the content so glass surfaces have something to refract.
struct AmbientBackground: View {
    var colors: [Color] = [.teal, .blue, .purple]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                blob(colors[0], size: w * 0.7).offset(x: -w * 0.3, y: -h * 0.35)
                blob(colors[1], size: w * 0.6).offset(x: w * 0.35, y: -h * 0.1)
                blob(colors[2], size: w * 0.55).offset(x: -w * 0.05, y: h * 0.45)
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle().fill(color.opacity(0.22)).frame(width: size, height: size).blur(radius: size * 0.35)
    }
}

// MARK: - Glass pieces

extension View {
    /// Rounded glass surface, optionally tinted (used for selected cards).
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0.opacity(0.28)) } ?? .regular
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
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
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.mix(with: .white, by: 0.15), color], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
    }
}

// MARK: - Disk visuals

/// Ring showing disk usage. The teal arc is what can be freed. `progress` draws an inner scan ring.
struct DiskRing<Center: View>: View {
    let total: Int64
    let free: Int64
    var reclaimable: Int64 = 0
    var progress: Double?
    var lineWidth: CGFloat = 18
    @ViewBuilder var center: Center

    private var usedFraction: Double { total > 0 ? Double(max(0, total - free)) / Double(total) : 0 }
    private var reclaimFraction: Double {
        total > 0 ? min(usedFraction, Double(reclaimable) / Double(total)) : 0
    }

    var body: some View {
        ZStack {
            rings.rotationEffect(.degrees(-90))
            center
        }
        .animation(.ui, value: reclaimable)
        .animation(.ui, value: free)
        .animation(.ui, value: progress)
    }

    private var rings: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: usedFraction - reclaimFraction)
                .stroke(
                    AngularGradient(colors: [.primary.opacity(0.35), .primary.opacity(0.6)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            if reclaimFraction > 0 {
                Circle()
                    .trim(from: usedFraction - reclaimFraction, to: usedFraction)
                    .stroke(
                        LinearGradient(colors: [.teal, .cyan], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .shadow(color: .teal.opacity(0.6), radius: 6)
            }
            if let progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .padding(lineWidth + 6)
            }
        }
    }
}

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

struct StatLine: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).monospacedDigit().fontWeight(.semibold).contentTransition(.numericText())
        }
        .font(.callout)
    }
}
