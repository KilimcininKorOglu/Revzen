/// The state of one app at the moment its Dock icon is clicked.
public struct AppWindowState: Sendable, Equatable {
    /// The app is the frontmost app.
    public var isFrontmost: Bool
    /// The app's focused window is a standard window that is not minimized.
    public var hasFocusedWindow: Bool
    /// The window that the previous Dock click minimized is still minimized,
    /// and the app stayed frontmost since that click.
    public var hasClickMinimizedWindow: Bool

    public init(isFrontmost: Bool, hasFocusedWindow: Bool, hasClickMinimizedWindow: Bool = false) {
        self.isFrontmost = isFrontmost
        self.hasFocusedWindow = hasFocusedWindow
        self.hasClickMinimizedWindow = hasClickMinimizedWindow
    }
}

/// What Revzen does with a click on a Dock icon.
public enum ClickAction: Sendable, Equatable {
    /// Let the Dock handle the click.
    case passThrough
    /// Minimize the focused window of the app.
    case minimizeFocused
    /// Restore the window that the previous Dock click minimized.
    case restoreClickMinimized
}

/// Maps the state of a clicked app to the Windows taskbar behavior: a click
/// on the active app minimizes its focused window, and the next click
/// restores that same window. macOS focuses another window of the app after
/// a minimize, so without the restore every click would minimize one more
/// window. Every other click keeps the Dock behavior, which activates the
/// app or restores the window minimized last.
public enum ClickPolicy {
    public static func action(for state: AppWindowState, isExcluded: Bool) -> ClickAction {
        guard !isExcluded, state.isFrontmost else { return .passThrough }
        if state.hasClickMinimizedWindow { return .restoreClickMinimized }
        return state.hasFocusedWindow ? .minimizeFocused : .passThrough
    }
}

/// The window that a Dock click minimized last, for each app.
///
/// An entry is valid only while the app stays frontmost: `generation` is the
/// app activation count at the click, and any later activation changes it.
/// A user who switches away and back expects the click to minimize again.
public struct ClickMinimizeMemory<Window: Sendable>: Sendable {
    private var entries: [Int32: (window: Window, generation: Int)] = [:]

    public init() {}

    public mutating func record(_ window: Window, pid: Int32, generation: Int) {
        entries[pid] = (window, generation)
    }

    /// The remembered window of the app, or nil when there is none or the
    /// app was activated again since the click. A stale entry is removed.
    public mutating func window(of pid: Int32, generation: Int) -> Window? {
        guard let entry = entries[pid] else { return nil }
        guard entry.generation == generation else {
            entries[pid] = nil
            return nil
        }
        return entry.window
    }

    public mutating func forget(_ pid: Int32) {
        entries[pid] = nil
    }
}
