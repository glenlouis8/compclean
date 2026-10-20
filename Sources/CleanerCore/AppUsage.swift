import CoreServices
import Foundation

/// When an app was last opened, as recorded by Spotlight.
public enum AppUsage {
    public static func lastUsed(_ app: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, app as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Apps not opened within `months`, oldest first. Apps Spotlight has no date for come last.
    public static func unused(_ apps: [AppInfo], months: Int, now: Date = Date(),
                              lastUsed: (URL) -> Date? = lastUsed) -> [(app: AppInfo, lastUsed: Date?)] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: now) ?? now
        return apps.map { ($0, lastUsed($0.url)) }
            .filter { $0.1.map { $0 < cutoff } ?? true }
            .sorted { a, b in
                switch (a.1, b.1) {
                case let (x?, y?): x < y
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): a.0.name < b.0.name
                }
            }
    }
}
