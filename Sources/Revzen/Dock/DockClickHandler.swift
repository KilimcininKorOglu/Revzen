import CoreGraphics
import Dispatch
import RevzenCore
import Synchronization

/// Turns a click on a Dock icon into the Windows taskbar behavior.
/// Runs on the event tap thread.
final class DockClickHandler: Sendable {
    private let dock: DockAX
    private let directory: AppDirectory
    /// A swallowed mouse down must take its mouse up with it, or the Dock
    /// sees a release without a press.
    private let swallowNextUp = Atomic<Bool>(false)
    /// AX writes block until the target app answers, so they run off the tap thread.
    private let actions = DispatchQueue(label: "com.kilimcininkoroglu.revzen.window-actions", qos: .userInteractive)

    /// Runs before the windows are minimized, while they are still capturable.
    private let beforeMinimize: @Sendable (pid_t) async -> Void

    init(dock: DockAX, directory: AppDirectory, beforeMinimize: @escaping @Sendable (pid_t) async -> Void) {
        self.dock = dock
        self.directory = directory
        self.beforeMinimize = beforeMinimize
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .leftMouseDown:
            let swallow = handleMouseDown(event)
            swallowNextUp.store(swallow, ordering: .relaxed)
            return swallow
        case .leftMouseUp:
            return swallowNextUp.exchange(false, ordering: .relaxed)
        default:
            return false
        }
    }

    private func handleMouseDown(_ event: CGEvent) -> Bool {
        // Modified clicks keep their Dock meaning, for example
        // Command-click reveals the app in Finder.
        guard event.flags.isDisjoint(with: .revzenModifiers),
              let item = dock.appItem(at: event.location),
              let app = directory.app(forBundleURL: item.appURL) else { return false }
        let excluded = directory.isExcluded(app)
        let isFrontmost = directory.isFrontmost(app.pid)
        // The AX read is skipped when the answer cannot change the action.
        let focused = !excluded && isFrontmost ? WindowService.focusedWindow(of: app.pid) : nil
        let state = AppWindowState(isFrontmost: isFrontmost, hasFocusedWindow: focused != nil)
        guard ClickPolicy.action(for: state, isExcluded: excluded) == .minimizeFocused,
              let focused else { return false }
        let pid = app.pid
        Task { [beforeMinimize, actions] in
            await beforeMinimize(pid)
            actions.async { WindowService.minimize(focused, pid: pid) }
        }
        return true
    }
}

extension CGEventFlags {
    static let revzenModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
}
