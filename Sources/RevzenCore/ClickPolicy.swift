/// The window state of one app at the moment its Dock icon is clicked.
public struct AppWindowState: Sendable, Equatable {
    /// The app is the frontmost app.
    public var isFrontmost: Bool
    /// Windows on the current Space that are not minimized.
    public var visibleCount: Int
    /// Windows that are minimized to the Dock.
    public var minimizedCount: Int

    public init(isFrontmost: Bool, visibleCount: Int, minimizedCount: Int) {
        self.isFrontmost = isFrontmost
        self.visibleCount = visibleCount
        self.minimizedCount = minimizedCount
    }
}

/// What Revzen does with a click on a Dock icon.
public enum ClickAction: Sendable, Equatable {
    /// Let the Dock handle the click.
    case passThrough
    /// Minimize every visible window of the app.
    case minimizeAll
    /// Restore every minimized window of the app and activate it.
    case restoreAll
}

/// Maps the window state of a clicked app to the Windows taskbar behavior.
public enum ClickPolicy {
    public static func action(for state: AppWindowState, isExcluded: Bool) -> ClickAction {
        if isExcluded {
            return .passThrough
        }
        if state.visibleCount > 0 {
            // A background app with visible windows only needs activation,
            // which the Dock already does.
            return state.isFrontmost ? .minimizeAll : .passThrough
        }
        // The Dock restores only one minimized window. Windows restores all.
        return state.minimizedCount > 0 ? .restoreAll : .passThrough
    }
}
