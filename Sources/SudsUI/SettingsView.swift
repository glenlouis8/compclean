import AppKit
import CleanerCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var ai: AIAssistant
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("menuBarShowsFree") private var menuBarShowsFree = false
    @AppStorage("menuBarShowsDot") private var menuBarShowsDot = true
    @AppStorage("appearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("seenWelcome") private var seenWelcome = false

    var body: some View {
        Form {
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Welcome screen") {
                    Button("Show again") { seenWelcome = false }
                }
            }
            Section("AI explanations") {
                Toggle("Explain items and summarize scans with Apple's on-device model",
                       isOn: Binding(get: { ai.enabled }, set: { ai.enabled = $0 }))
                    .disabled(!ai.isAvailable)
                LabeledContent("Status") { Text(ai.statusText).foregroundStyle(.secondary) }
                Text("It only explains what Suds already decided. It never chooses or removes anything, and nothing leaves your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Automatic cleaning") {
                Picker("Schedule", selection: Binding(get: { model.schedule }, set: { model.schedule = $0 })) {
                    ForEach(Schedule.choices) { Text($0.title).tag($0) }
                }
                Text("Off until you turn it on. Auto clean only covers app, browser and developer caches and old logs. Old downloads are never removed automatically.")
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
            Section("Menu bar") {
                Toggle("Show Suds in the menu bar", isOn: $showInMenuBar)
                Toggle("Show free space next to the icon", isOn: $menuBarShowsFree)
                    .disabled(!showInMenuBar)
                Toggle("Show a dot when over 1 GB of caches can be cleaned", isOn: $menuBarShowsDot)
                    .disabled(!showInMenuBar)
                Text(showInMenuBar
                     ? "Clean caches and check free space from the menu bar. Closing the window keeps Suds there."
                     : "Suds stays in the Dock instead, so you can always get back to it. Automatic cleaning keeps working.")
                    .font(.callout).foregroundStyle(.secondary)
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

#if DEBUG
#Preview("Settings") {
    SettingsView().previewEnvironment()
}
#endif
