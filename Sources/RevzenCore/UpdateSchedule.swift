import Foundation

/// Decides when the background update check runs.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// True when no check has run yet, when the last check is at least one
    /// interval old, or when the clock moved back before the last check.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }
}
