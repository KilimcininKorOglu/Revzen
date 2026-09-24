/// The state of one app at the moment its Dock icon is clicked.
public struct AppWindowState: Sendable, Equatable {
    /// The app is the frontmost app.
    public var isFrontmost: Bool
    /// The app's focused window is a standard window that is not minimized.
    public var hasFocusedWindow: Bool

    public init(isFrontmost: Bool, hasFocusedWindow: Bool) {
        self.isFrontmost = isFrontmost
        self.hasFocusedWindow = hasFocusedWindow
    }
}

/// What Revzen does with a click on a Dock icon.
public enum ClickAction: Sendable, Equatable {
    /// Let the Dock handle the click.
    case passThrough
    /// Minimize the focused window of the app.
    case minimizeFocused
}

/// Maps the state of a clicked app to the Windows taskbar behavior: a click
/// on the active app minimizes its focused window. Every other click keeps
/// the Dock behavior, which activates the app or restores the window
/// minimized last.
public enum ClickPolicy {
    public static func action(for state: AppWindowState, isExcluded: Bool) -> ClickAction {
        guard !isExcluded, state.isFrontmost, state.hasFocusedWindow else { return .passThrough }
        return .minimizeFocused
    }
}
