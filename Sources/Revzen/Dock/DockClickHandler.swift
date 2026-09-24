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

    init(dock: DockAX, directory: AppDirectory) {
        self.dock = dock
        self.directory = directory
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
        if excluded { return false }
        let state = WindowService.state(of: app.pid, isFrontmost: directory.isFrontmost(app.pid))
        switch ClickPolicy.action(for: state, isExcluded: excluded) {
        case .passThrough:
            return false
        case .minimizeAll:
            actions.async { WindowService.setAllMinimized(true, of: app.pid) }
            return true
        case .restoreAll:
            // The Dock click stays: the Dock activates the app and restores one
            // window, which AX activation of a background app cannot do
            // reliably. Revzen restores the other windows next to it.
            actions.async { WindowService.setAllMinimized(false, of: app.pid) }
            return false
        }
    }
}

extension CGEventFlags {
    static let revzenModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
}
