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
///
/// After the minimize, macOS focuses another window of the app. That window
/// is recorded, and when a later click finds another window focused, the user
/// chose it (with a click, Command-backtick or Mission Control), so the click
/// minimizes that window instead of restoring the remembered one.
public struct ClickMinimizeMemory<Window: Sendable & Equatable>: Sendable {
    /// The window macOS focused after the minimize.
    private enum FocusAfter: Sendable {
        case pending
        case window(Window?)
    }

    private struct Entry: Sendable {
        let window: Window
        let generation: Int
        let token: Int
        var focusAfter = FocusAfter.pending
    }

    private var entries: [Int32: Entry] = [:]
    private var lastToken = 0

    public init() {}

    /// Remembers the window and returns a token for this click. The minimize
    /// runs later, and only while `isLatest` still holds for the token.
    @discardableResult
    public mutating func record(_ window: Window, pid: Int32, generation: Int) -> Int {
        lastToken += 1
        entries[pid] = Entry(window: window, generation: generation, token: lastToken)
        return lastToken
    }

    /// True while the click with `token` is the last one that minimized a
    /// window of the app, and no restore or other click replaced it.
    public func isLatest(_ token: Int, for pid: Int32) -> Bool {
        entries[pid]?.token == token
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

    /// Records the window macOS focused after the minimize of the click with
    /// `token`, or nil when it focused none. Ignored for an older click.
    public mutating func recordFocusAfterMinimize(_ focused: Window?, pid: Int32, token: Int) {
        guard entries[pid]?.token == token else { return }
        entries[pid]?.focusAfter = .window(focused)
    }

    /// True when `focused` is not the window macOS focused after the
    /// minimize: the user moved to another window since the click. False
    /// while that window is not recorded yet, and with no focused window.
    public func focusMoved(of pid: Int32, focused: Window?) -> Bool {
        guard let focused, case .window(let after)? = entries[pid]?.focusAfter else { return false }
        return focused != after
    }

    public mutating func forget(_ pid: Int32) {
        entries[pid] = nil
    }
}
