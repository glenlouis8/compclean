import Foundation

public struct UninstallReport: Sendable {
    public var moves: [Move] = []
    public var failed: [(url: URL, reason: String)] = []
    public var adminCancelled = false

    public var trashed: [URL] { moves.map(\.from) }
    public var bytesFreed: Int64 { moves.reduce(0) { $0 + $1.size } }
}

/// Removes the chosen leftovers: user items via `Trasher`, root-owned ones via `PrivilegedRemover`.
/// The caller must quit the app first.
public struct Uninstaller: Sendable {
    public let policy: SafetyPolicy
    public let log: ActionLog
    public let mover: @Sendable (URL) throws -> URL?
    /// Tests turn this off so nothing can ever show an admin password prompt.
    public let allowAdmin: Bool

    public init(policy: SafetyPolicy, log: ActionLog = ActionLog(),
                mover: @escaping @Sendable (URL) throws -> URL? = Trasher.systemTrash, allowAdmin: Bool = true) {
        self.policy = policy
        self.log = log
        self.mover = mover
        self.allowAdmin = allowAdmin
    }

    public func remove(_ leftovers: [Leftover], of app: AppInfo) -> UninstallReport {
        log.write("UNINSTALL \(app.bundleID) (\(leftovers.count) items)")
        var report = UninstallReport()
        let sizes = Dictionary(leftovers.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })

        // Stop the app's own user launch agents before moving them.
        for item in leftovers where item.url.deletingLastPathComponent().lastPathComponent == "LaunchAgents"
            && policy.isInHome(item.url) {
            Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.url.path])
        }

        let userItems = leftovers.filter { !$0.needsAdmin }.map { ($0.url, $0.size) }
        let outcome = Trasher(policy: policy, log: log, mover: mover).trash(userItems, purpose: .uninstall)
        report.moves = outcome.moves
        report.failed = outcome.refused + outcome.failed

        let adminItems = leftovers.filter(\.needsAdmin).map(\.url) + outcome.needsAdmin
        if !adminItems.isEmpty && !allowAdmin {
            report.failed += adminItems.map { ($0, "needs admin, which is turned off") }
        } else if !adminItems.isEmpty {
            switch PrivilegedRemover(policy: policy, log: log).trash(adminItems, sizes: sizes) {
            case .success(let moved):
                report.moves += moved
            case .failure(.cancelled):
                report.adminCancelled = true
            case .failure(.failed(let msg)):
                report.failed += adminItems.map { ($0, msg) }
            }
        }
        return report
    }
}
