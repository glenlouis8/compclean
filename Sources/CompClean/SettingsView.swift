import AppKit
import CleanerCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Automatic cleaning") {
                Picker("Schedule", selection: Binding(get: { model.schedule }, set: { model.schedule = $0 })) {
                    ForEach(Schedule.allCases) { Text($0.title).tag($0) }
                }
                Text("Auto clean only covers app, browser and developer caches and old logs. Old downloads are never removed automatically.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Last auto clean") {
                    Text(model.lastAutoRun.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                }
            }
            Section("Developer junk") {
                Stepper("Projects untouched for \(model.devStaleDays) days or more",
                        value: model.$devStaleDays, in: 7...365, step: 7)
                LabeledContent("Project folders") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(model.devRootsDescription).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        HStack {
                            Button("Add folder…") { addProjectFolder() }
                            if !model.devRootsRaw.isEmpty { Button("Use defaults") { model.devRootsRaw = "" } }
                        }
                    }
                }
            }
            Section("App") {
                Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                LabeledContent("Full Disk Access") {
                    HStack {
                        Text(model.hasFullDiskAccess ? "Granted" : "Not granted")
                            .foregroundStyle(model.hasFullDiskAccess ? .green : .orange)
                        Button("Open Settings") { model.openFullDiskAccessSettings() }
                    }
                }
                LabeledContent("Action log") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.log.url]) }
                }
            }
            Section("Always protected") {
                Text("macOS and Apple files and apps, cookies, saved logins, browser history and storage, keychains, Mail, Messages, Photos and iCloud files. These rules are built in and can't be turned off.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func addProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: model.policy.home)
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let current = model.devRootsRaw.isEmpty ? model.devRoots.map(\.path) : model.devRootsRaw.split(separator: "\n").map(String.init)
        let added = panel.urls.map(\.path).filter { $0.hasPrefix(model.policy.home + "/") && !current.contains($0) }
        model.devRootsRaw = (current + added).joined(separator: "\n")
    }
}
