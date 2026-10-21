import AppKit
import CleanerCore
import SwiftUI

struct DevJunkView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        FinderScreen(store: model.devStore, title: "Developer junk",
                     subtitle: "Dependency and build folders in projects you haven't touched for \(model.devStaleDays)+ days, plus old Xcode files. Folders: \(model.devRootsDescription).",
                     symbol: "hammer", color: .purple,
                     emptyText: "No stale project junk found.") {
            DevToolsMenu()
        }
    }
}

/// Cleanups done by the tools themselves. They can't be put back, so each asks first.
struct DevToolsMenu: View {
    @State private var simulators: Int?
    @State private var docker: String?
    @State private var confirmSims = false
    @State private var confirmDocker = false
    @State private var result: String?

    var body: some View {
        Menu {
            Section("Done by the tool itself. Can't be put back.") {
                Button("Delete \(simulators ?? 0) unavailable simulators…") { confirmSims = true }
                    .disabled((simulators ?? 0) == 0)
                Button(docker == nil ? "Docker not running" : "Clean Docker (\(docker!))…") { confirmDocker = true }
                    .disabled(docker == nil)
            }
            if let result { Text(result) }
        } label: {
            Label("Tools", systemImage: "wrench.and.screwdriver")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .task {
            simulators = await Task.detached { DevTools.unavailableSimulatorCount() }.value
            docker = await Task.detached { DevTools.dockerReclaimable() }.value
        }
        .confirmationDialog("Delete unavailable simulators?", isPresented: $confirmSims) {
            Button("Delete \(simulators ?? 0) simulators", role: .destructive) {
                Task {
                    await Task.detached { DevTools.deleteUnavailableSimulators() }.value
                    simulators = await Task.detached { DevTools.unavailableSimulatorCount() }.value
                    result = "Unavailable simulators deleted."
                }
            }
        } message: {
            Text("These simulators belong to iOS versions Xcode no longer has. Xcode deletes them directly, so they can't be put back.")
        }
        .confirmationDialog("Clean up Docker?", isPresented: $confirmDocker) {
            Button("Run docker system prune", role: .destructive) {
                Task {
                    let out = await Task.detached { DevTools.dockerPrune() }.value
                    docker = await Task.detached { DevTools.dockerReclaimable() }.value
                    result = out
                }
            }
        } message: {
            Text("Removes stopped containers, unused networks, dangling images and build cache. Docker deletes them directly, so this can't be put back. Running containers and tagged images stay.")
        }
    }
}
