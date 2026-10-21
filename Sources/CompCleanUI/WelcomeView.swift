import AppKit
import SwiftUI

/// Shown once, on first launch: what CompClean promises, in plain words.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    private let promises: [(symbol: String, color: Color, title: String, detail: String)] = [
        ("lock.shield", .gray, "macOS is off-limits",
         "CompClean never touches system folders, Apple's apps or Apple's own files. Those rules are built in and can't be switched off."),
        ("person.badge.key", .green, "Your logins stay put",
         "Cookies, saved passwords, browser history and bookmarks are never cleaned, so you won't be signed out of anything."),
        ("eye", .blue, "You see everything first",
         "Every item comes with a plain explanation and a safety label. Your own files are never ticked for you."),
        ("arrow.uturn.backward.circle", .orange, "Everything can be undone",
         "Nothing is deleted. Items go to the Trash, and History can put any of them back where they were."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Welcome to CompClean").font(.system(size: 26, weight: .bold)).tracking(-0.3)
                Text("A free, open-source cleaner. Here's what it promises.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(promises, id: \.title) { p in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: p.symbol).font(.title2).foregroundStyle(p.color).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(.headline)
                            Text(p.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            HStack {
                Link("Read the safety rules", destination: URL(string: "https://github.com/glenlouis8/compclean#why-you-can-trust-it")!)
                Spacer()
                Button("Get started") { dismiss() }
                    .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 520)
    }
}

#Preview("Welcome") {
    WelcomeView()
}
