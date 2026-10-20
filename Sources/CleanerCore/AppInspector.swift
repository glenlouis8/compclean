import Foundation

public struct AppInfo: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String?
    public let teamID: String?
    public let isApple: Bool
}

public enum AppInspector {
    public static func inspect(_ url: URL) -> AppInfo? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let isApple = bundleID.lowercased().hasPrefix("com.apple") || CodeSignature.isAppleSigned(url)
        return AppInfo(
            url: url,
            name: name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String,
            teamID: CodeSignature.teamID(url),
            isApple: isApple
        )
    }

    public static func size(of url: URL) -> Int64 { FileSize.allocated(url) }

    /// Third-party apps in /Applications (one folder deep) and ~/Applications.
    public static func installedApps(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AppInfo] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var urls: [URL] = []
        for root in roots {
            for child in FileSize.children(root) where child.lastPathComponent != "Utilities" {
                if child.pathExtension == "app" {
                    urls.append(child)
                } else if FileSize.isDirectory(child) {
                    urls += FileSize.children(child).filter { $0.pathExtension == "app" }
                }
            }
        }
        let apps = urls.compactMap { url -> AppInfo? in
            guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { return nil }
            return inspect(url)
        }
        return apps.filter { !$0.isApple }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
