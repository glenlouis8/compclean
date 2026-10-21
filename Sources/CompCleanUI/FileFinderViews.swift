import CleanerCore
import SwiftUI

struct BigFilesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        FinderScreen(store: model.bigFilesStore, title: "Big files",
                     subtitle: "Your own files over \(sizeLabel(model.bigMinMB)), sorted by how long since you opened them. Nothing is ticked for you.",
                     symbol: "doc.zipper", color: .pink,
                     emptyText: "No files over \(sizeLabel(model.bigMinMB)) in your personal folders.") {
            Picker("Bigger than", selection: model.$bigMinMB) {
                Text("100 MB").tag(100)
                Text("250 MB").tag(250)
                Text("500 MB").tag(500)
                Text("1 GB").tag(1000)
                Text("5 GB").tag(5000)
            }
            .fixedSize()
            .onChange(of: model.bigMinMB) {
                if model.bigFilesStore.hasScanned { Task { await model.bigFilesStore.scan() } }
            }
        }
    }

    private func sizeLabel(_ mb: Int) -> String { mb >= 1000 ? "\(mb / 1000) GB" : "\(mb) MB" }
}

struct DuplicatesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DuplicatesScreen(store: model.duplicatesStore)
    }
}

private struct DuplicatesScreen: View {
    @ObservedObject var store: FinderStore

    private var extras: [ReviewItem] { store.items.filter { !$0.isKeeper } }

    var body: some View {
        FinderScreen(store: store, title: "Duplicates",
                     subtitle: "Files in Desktop, Documents and Downloads that are exact copies of each other, checked byte for byte.",
                     symbol: "square.on.square", color: .orange,
                     emptyText: "No duplicate files found.") {
            if store.hasScanned && !extras.isEmpty {
                Button {
                    store.selection = Set(extras.map(\.id))
                } label: {
                    Label("Select extras (\(ByteFormat.string(extras.reduce(0) { $0 + $1.size })))", systemImage: "checklist")
                }
                .buttonStyle(.glass)
                .help("Ticks every copy except the newest one in each group")
            }
        }
    }
}
