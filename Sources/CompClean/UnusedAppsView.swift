import AppKit
import CleanerCore
import SwiftUI

/// Apps you haven't opened in months, biggest wins first, one click to the uninstaller.
struct UnusedAppsView: View {
    @EnvironmentObject var model: AppModel

    private var rows: [(app: AppInfo, lastUsed: Date?)] { model.unusedApps }
    private var totalBytes: Int64 { rows.reduce(0) { $0 + (model.appSizes[$1.app.id] ?? 0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.usageLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Checking when you last opened each app…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView("You use all your apps", systemImage: "checkmark.seal",
                                       description: Text("Every app was opened in the last \(model.unusedMonths) months."))
            } else {
                List(rows, id: \.app.id) { row in UnusedAppRow(app: row.app, lastUsed: row.lastUsed) }
                    .probe("unused list")
                    .scrollContentBackground(.hidden)
            }
        }
        .task { if !model.usageLoaded { await model.loadUsage() } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "moon.zzz", color: .indigo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unused apps").font(.system(size: 24, weight: .bold)).tracking(-0.3)
                Text(model.usageLoaded
                     ? "\(rows.count) apps not opened in \(model.unusedMonths)+ months, using \(ByteFormat.string(totalBytes)). Uninstalling removes all their files too."
                     : "Apps you haven't opened in a long time.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Picker("Not opened in", selection: model.$unusedMonths) {
                Text("3 months").tag(3)
                Text("6 months").tag(6)
                Text("1 year").tag(12)
                Text("2 years").tag(24)
            }
            .fixedSize()
        }
        .padding(22)
        .glassCard(cornerRadius: 24)
        .padding(16)
        .probe("unused header")
    }
}

struct UnusedAppRow: View {
    @EnvironmentObject var model: AppModel
    let app: AppInfo
    let lastUsed: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                Text(lastUsed.map { "Last opened \($0.formatted(.relative(presentation: .named)))" }
                     ?? "No record of it being opened")
                    .font(.callout).foregroundStyle(lastUsed == nil ? .orange : .secondary)
                    .help(lastUsed == nil ? "Spotlight has no open date for this app. It may never have been opened, or Spotlight indexing was off." : "")
            }
            Spacer()
            if let size = model.appSizes[app.id] {
                Text(ByteFormat.string(size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button("Uninstall…") { model.openInUninstaller(app) }
                .buttonStyle(.glass)
        }
        .padding(.vertical, 4)
    }
}
