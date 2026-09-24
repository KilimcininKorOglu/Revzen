/// Picks the next window when scrolling over a Dock icon.
public enum WindowCycler {
    /// The index after `current`, `step` positions away, wrapping at both
    /// ends. Without a current window, forward starts at the first window and
    /// backward at the last. Nil when there is no window.
    public static func next(count: Int, current: Int?, step: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return step >= 0 ? 0 : count - 1 }
        return ((current + step) % count + count) % count
    }
}

/// Turns scroll wheel deltas into window steps. A mouse wheel sends one line
/// per notch; a trackpad sends many small pixel deltas, which add up to a
/// step only after `pixelThreshold`.
public struct ScrollStepper: Sendable {
    public static let lineThreshold = 1.0
    public static let pixelThreshold = 40.0

    private var accumulated = 0.0

    public init() {}

    /// Adds one scroll event. Returns +1 for the next window (scroll down),
    /// -1 for the previous one (scroll up), 0 while below the threshold.
    /// One event never moves more than one step, so a fast flick does not
    /// skip windows.
    public mutating func add(_ delta: Double, continuous: Bool) -> Int {
        if delta != 0, accumulated != 0, (delta > 0) != (accumulated > 0) {
            accumulated = 0  // a direction change starts over
        }
        accumulated += delta
        let threshold = continuous ? Self.pixelThreshold : Self.lineThreshold
        guard abs(accumulated) >= threshold else { return 0 }
        let step = accumulated > 0 ? -1 : 1
        accumulated = 0
        return step
    }

    public mutating func reset() {
        accumulated = 0
    }
}
