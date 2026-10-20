import Foundation

/// Moves root-owned uninstall leftovers to the Trash with one admin password prompt.
/// Only third-party items that pass `SafetyPolicy` for `.uninstall` ever reach the script.
public struct PrivilegedRemover: Sendable {
    public let policy: SafetyPolicy
    public let log: ActionLog

    public init(policy: SafetyPolicy, log: ActionLog = ActionLog()) {
        self.policy = policy
        self.log = log
    }

    public enum Failure: Error, Sendable, Equatable { case cancelled, failed(String) }

    public func trash(_ urls: [URL], sizes: [URL: Int64] = [:]) -> Result<[Move], Failure> {
        let allowed = urls.filter { policy.canTrash($0, for: .uninstall) }
        for url in urls where !allowed.contains(url) { log.write("REFUSED (admin) \(url.path)") }
        guard !allowed.isEmpty else { return .success([]) }
        let dests = Self.destinations(for: allowed, home: policy.home)
        if let failure = runAsAdmin(Self.script(for: allowed, dests: dests, uid: getuid())) {
            return .failure(failure)
        }
        for url in allowed { log.write("TRASHED (admin) \(url.path)") }
        return .success(zip(allowed, dests).map { Move(from: $0, to: $1, size: sizes[$0] ?? 0, admin: true) })
    }

    /// Moves admin-owned items from the Trash back to where they were.
    public func putBack(_ pairs: [(trashed: URL, original: URL)]) -> Failure? {
        let trash = policy.home + "/.Trash/"
        let safe = pairs.filter {
            (SafetyPolicy.realPath($0.trashed.path) ?? $0.trashed.path).hasPrefix(trash) && Self.isRestorable($0.original)
        }
        guard !safe.isEmpty else { return .failed("Nothing to put back") }
        let lines = safe.map { "/bin/mv -n \(Self.shellQuote($0.trashed.path)) \(Self.shellQuote($0.original.path))" }
        if let failure = runAsAdmin((["set -e"] + lines).joined(separator: "; ")) { return failure }
        for p in safe { log.write("PUT BACK (admin) \(p.original.path)") }
        return nil
    }

    /// Admin put-back only goes into the third-party folders admin removal could have taken from.
    static func isRestorable(_ original: URL) -> Bool {
        let comps = original.standardizedFileURL.path.split(separator: "/").map(String.init)
        if comps.count == 2, comps[0] == "Applications", comps[1].hasSuffix(".app") { return true }
        if comps.count == 3, comps[0] == "Applications", comps[2].hasSuffix(".app"), comps[1] != "Utilities" { return true }
        return comps.count >= 3 && comps[0] == "Library" && LeftoverFinder.systemRoots.contains(comps[1])
            && !comps.joined(separator: "/").lowercased().contains("com.apple")
    }

    private func runAsAdmin(_ script: String) -> Failure? {
        let apple = "do shell script \"\(Self.appleScriptEscape(script))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", apple]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return .failed(error.localizedDescription) }
        process.waitUntilExit()
        let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            return message.contains("-128") ? .cancelled : .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static func destinations(for urls: [URL], home: String) -> [URL] {
        let stamp = Int(Date().timeIntervalSince1970)
        return urls.enumerated().map { i, url in
            URL(fileURLWithPath: "\(home)/.Trash/\(url.lastPathComponent) \(stamp)-\(i)")
        }
    }

    static func script(for urls: [URL], dests: [URL], uid: uid_t) -> String {
        var lines = ["set -e"]
        for (url, dest) in zip(urls, dests) {
            let path = url.path
            let parent = url.deletingLastPathComponent().lastPathComponent
            if parent == "LaunchDaemons" {
                lines.append("/bin/launchctl bootout system \(shellQuote(path)) 2>/dev/null || true")
            } else if parent == "LaunchAgents" {
                lines.append("/bin/launchctl bootout gui/\(uid) \(shellQuote(path)) 2>/dev/null || true")
            }
            lines.append("/bin/mv -n \(shellQuote(path)) \(shellQuote(dest.path))")
        }
        return lines.joined(separator: "; ")
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
