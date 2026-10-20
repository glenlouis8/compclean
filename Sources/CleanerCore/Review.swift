import Foundation

/// How careful the user should be with an item. Shown as a badge on every row.
public enum Safety: String, Sendable, Codable, CaseIterable {
    case rebuildsItself  // caches and logs: the app recreates them
    case leftover        // belongs to an app that's gone
    case reviewFirst     // probably junk, but worth a look
    case yourFile        // the user's own file

    public var title: String {
        switch self {
        case .rebuildsItself: "Rebuilds itself"
        case .leftover: "Leftover"
        case .reviewFirst: "Review first"
        case .yourFile: "Your file"
        }
    }
}

/// Plain-language answer to "what is this and why can it go?".
public struct Explanation: Hashable, Sendable {
    public var title: String
    public var ownerName: String?
    /// Path of the owning app bundle, for its icon.
    public var ownerAppPath: String?
    public var safety: Safety
    public var reason: String
    public var lastUsed: Date?

    public init(title: String, ownerName: String? = nil, ownerAppPath: String? = nil,
                safety: Safety, reason: String, lastUsed: Date? = nil) {
        self.title = title
        self.ownerName = ownerName
        self.ownerAppPath = ownerAppPath
        self.safety = safety
        self.reason = reason
        self.lastUsed = lastUsed
    }
}

/// One thing a finder suggests removing. Every finder returns these, and every screen lists them.
public struct ReviewItem: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public var explanation: Explanation
    /// Section the item is listed under, e.g. "Spotify (not installed)".
    public var group: String
    public var preselected: Bool
    public let purpose: Purpose
    /// Duplicates: the copy suggested to keep. Never offered by "Select extras".
    public var isKeeper: Bool

    public init(url: URL, size: Int64, explanation: Explanation, group: String,
                preselected: Bool, purpose: Purpose, isKeeper: Bool = false) {
        self.url = url
        self.size = size
        self.explanation = explanation
        self.group = group
        self.preselected = preselected
        self.purpose = purpose
        self.isKeeper = isKeeper
    }
}
