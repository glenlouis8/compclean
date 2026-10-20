import Foundation

public enum CleanCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case userCaches
    case browserCaches
    case oldLogs
    case devCaches
    case oldDownloads

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .userCaches: "App caches"
        case .browserCaches: "Browser caches"
        case .oldLogs: "Old logs"
        case .devCaches: "Developer caches"
        case .oldDownloads: "Old downloads"
        }
    }

    public var detail: String {
        switch self {
        case .userCaches: "Third-party app caches in ~/Library/Caches. Apps rebuild these."
        case .browserCaches: "Cached pages and code only. Cookies, logins and history are never touched."
        case .oldLogs: "Third-party log files older than 7 days."
        case .devCaches: "Homebrew, npm, Yarn, pip, uv and Xcode DerivedData."
        case .oldDownloads: "Items in Downloads untouched for 90+ days. Review before removing."
        }
    }

    public var symbol: String {
        switch self {
        case .userCaches: "archivebox"
        case .browserCaches: "globe"
        case .oldLogs: "doc.text"
        case .devCaches: "hammer"
        case .oldDownloads: "arrow.down.circle"
        }
    }

    /// Whether the scheduled auto-clean may remove this category without a preview.
    public var autoSafe: Bool { self != .oldDownloads }

    public var purpose: Purpose { self == .oldDownloads ? .reviewDownloads : .clean }
}

public struct Finding: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let category: CleanCategory

    public init(url: URL, size: Int64, category: CleanCategory) {
        self.url = url
        self.size = size
        self.category = category
    }

    public var displayName: String { url.lastPathComponent }
}

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
