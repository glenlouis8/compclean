import SwiftUI

/// Debug aid for diagnosing layout without screenshots. Does nothing unless these are set:
/// - COMPCLEAN_LAYOUT_LOG=<file>: tagged views append their on-screen frame to that file.
/// - COMPCLEAN_PANE=<pane name>: open on that screen (e.g. "Unused apps").
struct LayoutProbe: ViewModifier {
    let name: String
    static let file = ProcessInfo.processInfo.environment["COMPCLEAN_LAYOUT_LOG"]

    func body(content: Content) -> some View {
        if let file = Self.file {
            content.background(GeometryReader { geo in
                Color.clear
                    .onAppear { Self.write(file, name, geo) }
                    .onChange(of: geo.frame(in: .global)) { Self.write(file, name, geo) }
            })
        } else {
            content
        }
    }

    static func write(_ file: String, _ name: String, _ geo: GeometryProxy) {
        let f = geo.frame(in: .global)
        let line = "\(name): x=\(Int(f.minX)) y=\(Int(f.minY)) w=\(Int(f.width)) h=\(Int(f.height))\n"
        if let h = FileHandle(forWritingAtPath: file) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(toFile: file, atomically: true, encoding: .utf8)
        }
    }

    static var startPane: Pane? {
        ProcessInfo.processInfo.environment["COMPCLEAN_PANE"].flatMap(Pane.init(rawValue:))
    }
}

extension View {
    func probe(_ name: String) -> some View { modifier(LayoutProbe(name: name)) }
}
