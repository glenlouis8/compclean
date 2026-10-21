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

    /// Automatic cleaning stays off until the person turns it on.
    public static let defaultValue = Schedule.off

    /// What Settings offers. The one-minute schedule is for testing builds only.
    public static var choices: [Schedule] {
        #if DEBUG
        allCases
        #else
        [.off, .daily, .weekly]
        #endif
    }

    /// `lastRun` is the last clean, or when the schedule was turned on. With neither, it's never due,
    /// so nothing is cleaned the moment someone opens the app.
    public func isDue(lastRun: Date?, now: Date = Date()) -> Bool {
        guard let interval, let lastRun else { return false }
        return now.timeIntervalSince(lastRun) >= interval
    }
}
