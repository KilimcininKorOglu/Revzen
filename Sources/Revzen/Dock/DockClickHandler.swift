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
    /// Waits for the window macOS focuses after a minimize. A separate queue,
    /// so the wait never delays a restore on `actions`.
    private let focusWatch = DispatchQueue(label: "com.kilimcininkoroglu.revzen.focus-watch", qos: .utility)
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
        let focused = active ? WindowService.focusedWindow(of: app.pid) : nil
        let restorable = active ? clickMinimizedWindow(of: app.pid, generation: generation, focused: focused) : nil
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
    /// minimized and the user did not move to another window of the app. A
    /// window that the user restored some other way is forgotten.
    private func clickMinimizedWindow(of pid: pid_t, generation: Int, focused: AXElement?) -> AXElement? {
        guard let window = clickMinimized.withLock({ $0.window(of: pid, generation: generation) }) else { return nil }
        guard window.bool(kAXMinimizedAttribute) == true else {
            clickMinimized.withLock { $0.forget(pid) }
            return nil
        }
        guard !clickMinimized.withLock({ $0.focusMoved(of: pid, focused: focused) }) else {
            DebugLog.event(.click, "pid \(pid): another window was focused after the minimize, it is minimized instead")
            clickMinimized.withLock { $0.forget(pid) }
            return nil
        }
        return window
    }

    /// The AX write waits for the snapshot. By then a later click can have
    /// restored or replaced the window, so the job runs only for the latest
    /// click. The check runs on `actions`, in order with the restore job.
    private func minimize(_ window: AXElement, pid: pid_t, generation: Int) -> Bool {
        let token = clickMinimized.withLock { $0.record(window, pid: pid, generation: generation) }
        Task { [self] in
            await beforeMinimize(pid)
            actions.async { [self] in
                guard clickMinimized.withLock({ $0.isLatest(token, for: pid) }) else {
                    DebugLog.event(.click, "pid \(pid): minimize dropped, a later click restored or replaced the window")
                    return
                }
                WindowService.minimize(window, pid: pid)
                watchFocus(after: window, pid: pid, token: token, deadline: .now() + Self.focusWait)
            }
        }
        return true
    }

    /// The longest wait for macOS to focus another window after a minimize.
    /// Measured: about 400 ms, the length of the minimize animation.
    private static let focusWait: DispatchTimeInterval = .seconds(2)

    /// Records the window that macOS focuses after the minimize, or nil when
    /// it focuses none before the deadline. Stops when a later click
    /// replaced this one.
    private func watchFocus(after minimized: AXElement, pid: pid_t, token: Int, deadline: DispatchTime) {
        guard clickMinimized.withLock({ $0.isLatest(token, for: pid) }) else { return }
        let focused = AXElement.application(pid, timeout: AXElement.actionTimeout).element(kAXFocusedWindowAttribute)
        if let focused, focused != minimized {
            clickMinimized.withLock { $0.recordFocusAfterMinimize(focused, pid: pid, token: token) }
            DebugLog.event(.click, "pid \(pid): macOS focused another window after the minimize")
            return
        }
        guard DispatchTime.now() < deadline else {
            clickMinimized.withLock { $0.recordFocusAfterMinimize(nil, pid: pid, token: token) }
            DebugLog.event(.click, "pid \(pid): no other window was focused after the minimize")
            return
        }
        focusWatch.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
            watchFocus(after: minimized, pid: pid, token: token, deadline: deadline)
        }
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
