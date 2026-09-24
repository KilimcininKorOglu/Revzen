import ApplicationServices
import CoreGraphics
import Dispatch
import RevzenCore
import Synchronization

/// Turns a click on a Dock icon into the Windows taskbar behavior: a click
/// minimizes the focused window, and the next click restores it.
/// Runs on the event tap thread.
final class DockClickHandler: Sendable {
    private let dock: DockAX
    private let directory: AppDirectory
    /// A swallowed mouse down must take its mouse up with it, or the Dock
    /// sees a release without a press.
    private let swallowNextUp = Atomic<Bool>(false)
    /// AX writes block until the target app answers, so they run off the tap thread.
    private let actions = DispatchQueue(label: "com.kilimcininkoroglu.revzen.window-actions", qos: .userInteractive)
    /// The window each app's last Dock click minimized, so the next click
    /// restores it instead of minimizing the window macOS focused next.
    private let clickMinimized = Mutex(ClickMinimizeMemory<AXElement>())

    /// Runs before the windows are minimized, while they are still capturable.
    private let beforeMinimize: @Sendable (pid_t) async -> Void
    /// Runs when a click opens the Dock menu of an app icon.
    private let onMenuClick: @Sendable () -> Void

    init(
        dock: DockAX,
        directory: AppDirectory,
        beforeMinimize: @escaping @Sendable (pid_t) async -> Void,
        onMenuClick: @escaping @Sendable () -> Void
    ) {
        self.dock = dock
        self.directory = directory
        self.beforeMinimize = beforeMinimize
        self.onMenuClick = onMenuClick
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .leftMouseDown where event.flags.contains(.maskControl), .rightMouseDown:
            // Control-click and right click open the Dock menu. The Dock keeps the click.
            if let item = dock.appItem(at: event.location) {
                DebugLog.event(.click, "menu click on \(item.logName) at \(event.location.logText), preview hides")
                onMenuClick()
            }
            return false
        case .leftMouseDown:
            let swallow = handleMouseDown(event)
            swallowNextUp.store(swallow, ordering: .relaxed)
            return swallow
        case .leftMouseUp:
            let swallow = swallowNextUp.exchange(false, ordering: .relaxed)
            if swallow {
                DebugLog.event(.click, "mouse up swallowed with its mouse down")
            }
            return swallow
        default:
            return false
        }
    }
}

extension DockClickHandler {
    private func handleMouseDown(_ event: CGEvent) -> Bool {
        guard let item = dock.appItem(at: event.location) else { return false }
        // Modified clicks keep their Dock meaning, for example
        // Command-click reveals the app in Finder.
        guard event.flags.isDisjoint(with: .revzenModifiers) else {
            DebugLog.event(.click, "\(item.logName): modified click, the Dock handles it")
            return false
        }
        guard let app = directory.app(forBundleURL: item.appURL) else {
            DebugLog.event(.click, "\(item.logName): not running, the Dock launches it")
            return false
        }
        let excluded = directory.isExcluded(app)
        let isFrontmost = directory.isFrontmost(app.pid)
        let generation = directory.activationGeneration
        // The AX reads are skipped when the answer cannot change the action.
        let active = !excluded && isFrontmost
        let restorable = active ? clickMinimizedWindow(of: app.pid, generation: generation) : nil
        let focused = active && restorable == nil ? WindowService.focusedWindow(of: app.pid) : nil
        let state = AppWindowState(
            isFrontmost: isFrontmost,
            hasFocusedWindow: focused != nil,
            hasClickMinimizedWindow: restorable != nil
        )
        let action = ClickPolicy.action(for: state, isExcluded: excluded)
        DebugLog.event(
            .click,
            "\(app.logName): frontmost=\(isFrontmost) excluded=\(excluded) "
                + "focusedWindow=\(focused != nil) clickMinimized=\(restorable != nil) -> \(action)")
        switch action {
        case .passThrough:
            return false
        case .minimizeFocused:
            return focused.map { minimize($0, pid: app.pid, generation: generation) } ?? false
        case .restoreClickMinimized:
            return restorable.map { restore($0, pid: app.pid) } ?? false
        }
    }

    /// The window that the previous click minimized, while it is still
    /// minimized. A window that the user restored some other way is forgotten.
    private func clickMinimizedWindow(of pid: pid_t, generation: Int) -> AXElement? {
        guard let window = clickMinimized.withLock({ $0.window(of: pid, generation: generation) }) else { return nil }
        guard window.bool(kAXMinimizedAttribute) == true else {
            clickMinimized.withLock { $0.forget(pid) }
            return nil
        }
        return window
    }

    private func minimize(_ window: AXElement, pid: pid_t, generation: Int) -> Bool {
        clickMinimized.withLock { $0.record(window, pid: pid, generation: generation) }
        Task { [beforeMinimize, actions] in
            await beforeMinimize(pid)
            actions.async { WindowService.minimize(window, pid: pid) }
        }
        return true
    }

    private func restore(_ window: AXElement, pid: pid_t) -> Bool {
        clickMinimized.withLock { $0.forget(pid) }
        actions.async { WindowService.focus(AppWindow(element: window, pid: pid, isMinimized: true)) }
        return true
    }
}

extension CGEventFlags {
    static let revzenModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
}
