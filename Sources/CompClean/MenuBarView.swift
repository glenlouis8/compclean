import AppKit
import CleanerCore
import SwiftUI

/// Control Center–style popover: disk ring, what's ready to clean, one big action.
struct MenuBarView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showDone = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                DiskRing(total: model.diskTotal, free: model.diskFree,
                         reclaimable: model.quickEstimate ?? 0, lineWidth: 10) {
                    VStack(spacing: 0) {
                        Text(shortBytes(model.diskFree)).font(.system(.title3, design: .rounded).bold())
                            .contentTransition(.numericText())
                        Text("free").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready to clean").font(.caption).foregroundStyle(.secondary)
                    Group {
                        if model.isEstimating && model.quickEstimate == nil {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(ByteFormat.string(model.quickEstimate ?? 0))
                                .contentTransition(.numericText())
                        }
                    }
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .frame(height: 34, alignment: .leading)
                    Label(autoCleanText, systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            cleanButton

            HStack(spacing: 10) {
                Label("\(ByteFormat.string(Int64(model.totalFreed))) moved to Trash", systemImage: "trash")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Space comes back when you empty the Trash.")
                Spacer()
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        GlassIconButton(symbol: "macwindow", help: "Open CompClean", size: 30) {
                            openWindow(id: "main")
                            NSApp.activate()
                        }
                        GlassIconButton(symbol: "power", help: "Quit CompClean", size: 30) { NSApp.terminate(nil) }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .task {
            model.refreshDisk()
            await model.refreshQuickEstimate()
        }
    }

    private var cleanButton: some View {
        Button {
            Task {
                await model.quickClean(reason: "clean")
                withAnimation(.pop) { showDone = true }
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.ui) { showDone = false }
            }
        } label: {
            HStack(spacing: 8) {
                if model.isCleaning {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Cleaning…")
                } else if showDone {
                    Image(systemName: "checkmark.circle.fill").transition(.scale.combined(with: .opacity))
                    Text("\(ByteFormat.string(model.lastQuickFreed ?? 0)) moved to Trash")
                } else {
                    Image(systemName: "sparkles")
                    Text((model.quickEstimate ?? 0) > 0 ? "Clean \(ByteFormat.string(model.quickEstimate ?? 0))" : "Clean now")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentTransition(.numericText())
        }
        .buttonStyle(.glassProminent)
        .tint(showDone ? .green : .accentColor)
        .controlSize(.extraLarge)
        .disabled(model.isCleaning || model.isEstimating)
    }

    private var autoCleanText: String {
        guard model.schedule != .off else { return "Auto clean off" }
        guard let next = model.nextAutoRun, next > Date() else { return "Auto clean \(model.schedule.title.lowercased())" }
        return "Next auto clean \(next.formatted(.relative(presentation: .named)))"
    }

    /// "321 GB" without decimals, so it fits in the ring.
    private func shortBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        f.isAdaptive = false
        return f.string(fromByteCount: bytes)
    }
}
