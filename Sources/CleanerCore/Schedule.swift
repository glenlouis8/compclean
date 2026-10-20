import Foundation

public enum Schedule: String, CaseIterable, Sendable, Identifiable {
    case off, daily, weekly, everyMinute

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .everyMinute: "Every minute (testing)"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .off: nil
        case .daily: 86_400
        case .weekly: 7 * 86_400
        case .everyMinute: 60
        }
    }

    public func isDue(lastRun: Date?, now: Date = Date()) -> Bool {
        guard let interval else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval
    }
}
