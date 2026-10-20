import AppKit
import Foundation

/// Finds files in your Library left behind by apps that are no longer installed.
public struct OrphanFinder: Sendable {
    public let policy: SafetyPolicy
    public let home: URL
    /// Lowercased bundle ids of installed and running apps.
    public let knownIDs: Set<String>
    /// Extra installed check, LaunchServices by default. Tests turn it off.
    public let isRegistered: @Sendable (String) -> Bool
    public let now: Date

    public init(policy: SafetyPolicy, knownIDs: Set<String>,
                isRegistered: @escaping @Sendable (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
                now: Date = Date()) {
        self.policy = policy
        self.home = URL(fileURLWithPath: policy.home)
        self.knownIDs = Set(knownIDs.map { $0.lowercased() })
        self.isRegistered = isRegistered
        self.now = now
    }

    /// Library folder -> what to call its contents.
    static let roots: [(path: String, label: String)] = [
        ("Application Support", "app data"), ("Caches", "cache"), ("Preferences", "settings"),
        ("Preferences/ByHost", "settings"), ("Containers", "sandbox data"), ("Group Containers", "shared data"),
        ("Saved Application State", "saved windows"), ("HTTPStorages", "web storage"), ("WebKit", "web data"),
        ("Cookies", "cookies"), ("Logs", "logs"), ("LaunchAgents", "background task"),
        ("Application Scripts", "scripts"),
    ]

    /// Prefixes that belong to tools without an app bundle, so "no app installed" means nothing.
    static let toolPrefixes = ["homebrew.", "org.homebrew", "com.glenlouis.compclean", "local.", "org.nixos",
                               "org.macports", "org.swift.", "org.llvm.", "com.docker.cli"]

    /// macOS parts that use old, non-"com.apple" names. Never treated as leftovers (SafetyPolicy refuses them too).
    static let applePrefixes = SafetyPolicy.appleLegacyPrefixes

    /// Frameworks bundled inside other apps (updaters, analytics). Their files belong to apps
    /// that are still installed, so "no app with this id" doesn't mean the app is gone.
    static let sharedFrameworks = ["org.sparkle-project.", "com.segment.", "com.launchdarkly.", "io.sentry.",
                                   "com.crashlytics.", "com.google.firebase", "com.firebase.", "com.mixpanel.",
                                   "com.amplitude.", "com.braze.", "com.onesignal.", "com.microsoft.appcenter",
                                   "com.datadoghq.", "com.bugsnag.", "com.instabug.", "com.revenuecat.",
                                   "com.paddle.", "com.devmate.", "net.hockeyapp.", "com.getsentry.",
                                   "com.plausiblelabs.", "com.squirrel.", "com.github.electron"]

    /// Vendors too broad to treat as one company.
    static let sharedVendors: Set<String> = ["com.github", "io.github", "com.gitlab", "org.sourceforge", "net.sourceforge"]

    static let staleAge: TimeInterval = 30 * 86_400

    public func find() -> [ReviewItem] {
        let lib = home.appendingPathComponent("Library")
        var hits: [(url: URL, root: (path: String, label: String), shownID: String)] = []
        var seen: Set<String> = []
        for root in Self.roots {
            for child in FileSize.children(lib.appendingPathComponent(root.path)) {
                guard !seen.contains(child.path),
                      let shownID = Self.displayID(from: child.lastPathComponent, root: root.path),
                      isOrphan(shownID.lowercased()),
                      root.path != "LaunchAgents" || !Self.launchAgentProgramExists(child),
                      policy.canTrash(child, for: .uninstall)
                else { continue }
                seen.insert(child.path)
                hits.append((child, root, shownID))
            }
        }

        // One group per maker, named after its shortest id (usually the main app).
        let byVendor = Dictionary(grouping: hits) { Self.vendor(of: $0.shownID.lowercased()) }
        let groupName = byVendor.mapValues { group in
            ItemExplainer.guessName(fromBundleID: group.map(\.shownID).min { $0.count < $1.count }!)
        }

        var items: [ReviewItem] = []
        for hit in hits {
            let id = hit.shownID.lowercased()
            let app = groupName[Self.vendor(of: id)] ?? ItemExplainer.guessName(fromBundleID: hit.shownID)
            let size = FileSize.allocated(hit.url)
            let lastUsed = ItemExplainer.lastUsed(hit.url)
            let stale = lastUsed.map { now.timeIntervalSince($0) > Self.staleAge } ?? true
            let isAgent = hit.root.path == "LaunchAgents"
            let reason = isAgent
                ? "A background task for \(app), which is no longer installed. The program it starts is gone too."
                : "\(app) isn't installed anymore, but it left this behind (\(hit.shownID)). No installed app uses it."
            items.append(ReviewItem(
                url: hit.url, size: size,
                explanation: Explanation(title: "\(ItemExplainer.guessName(fromBundleID: hit.shownID)) · \(hit.root.label)",
                                         safety: .leftover, reason: reason, lastUsed: lastUsed),
                group: "\(app) (not installed)",
                preselected: stale && !isAgent,
                purpose: .uninstall))
        }
        // Biggest leftover apps first, biggest items first within each.
        let totals = Dictionary(grouping: items, by: \.group).mapValues { $0.reduce(0) { $0 + $1.size } }
        return items.sorted { a, b in
            let ta = totals[a.group] ?? 0, tb = totals[b.group] ?? 0
            return ta != tb ? ta > tb : (a.group != b.group ? a.group < b.group : a.size > b.size)
        }
    }

    func isOrphan(_ id: String) -> Bool {
        let skip = Self.toolPrefixes + Self.applePrefixes + Self.sharedFrameworks
        if skip.contains(where: { id.hasPrefix($0) }) { return false }
        if knownIDs.contains(id) { return false }
        // Helpers and plug-ins share their app's id as a prefix, in either direction.
        if knownIDs.contains(where: { id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return false }
        let vendor = Self.vendor(of: id)
        if knownIDs.contains(where: { Self.vendor(of: $0) == vendor }) { return false }
        if isRegistered(id) { return false }
        return true
    }

    static func vendor(of id: String) -> String {
        let parts = id.split(separator: ".")
        let two = parts.prefix(2).joined(separator: ".")
        return sharedVendors.contains(two) ? parts.prefix(3).joined(separator: ".") : two
    }

    /// Extracts a lowercased bundle id from a Library item name, or nil if it doesn't look like one.
    static func bundleID(from rawName: String, root: String) -> String? {
        displayID(from: rawName, root: root)?.lowercased()
    }

    /// Same as `bundleID`, keeping the original capitalization for display names.
    static func displayID(from rawName: String, root: String) -> String? {
        var name = rawName
        for suffix in [".plist", ".savedState", ".binarycookies"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        var parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        // Developer team id prefix (e.g. UBF8T346G9.) and "group." can appear in any of these folders.
        if let first = parts.first, first.count == 10, first.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            parts.removeFirst()
        }
        if parts.first == "group" { parts.removeFirst() }
        if root == "Preferences/ByHost", let last = parts.last, last.count >= 12,
           last.allSatisfy({ $0.isHexDigit || $0 == "-" }) {
            parts.removeLast() // per-machine UUID
        }
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty && !$0.contains(" ") }) else { return nil }
        let id = parts.joined(separator: ".")
        let lower = id.lowercased()
        if lower.hasPrefix("com.apple") || lower.hasPrefix("apple.") || lower.contains("com.apple.") { return nil }
        return id
    }

    /// A launch agent whose program still exists belongs to something still installed.
    static func launchAgentProgramExists(_ plist: URL) -> Bool {
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any] else { return true }
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
        guard let program, program.hasPrefix("/") else { return true } // can't tell, so leave it alone
        return FileManager.default.fileExists(atPath: program)
    }

    /// Stops leftover background tasks before their plists move to the Trash.
    public static func prepareForRemoval(_ items: [ReviewItem]) {
        for item in items where item.url.deletingLastPathComponent().lastPathComponent == "LaunchAgents" {
            Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.url.path])
        }
    }
}
