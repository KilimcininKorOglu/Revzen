import CoreGraphics
import Dispatch
import RevzenCore
import Synchronization

/// Cycles through an app's windows when the wheel scrolls over its Dock
/// icon. Runs on the event tap thread.
final class DockScrollHandler: Sendable {
    private struct State {
        var stepper = ScrollStepper()
        var pid: pid_t?
        var pending = PendingCycle<pid_t>()
    }

    private let dock: DockAX
    private let directory: AppDirectory
    private let state = Mutex(State())
    /// One cycle at a time, in order, off the tap thread. Steps that arrive
    /// while a cycle waits merge into it, so a slow app does not collect a
    /// queue of cycles that run after the scrolling ended.
    private let actions = DispatchQueue(label: "com.kilimcininkoroglu.revzen.scroll-actions", qos: .userInteractive)

    init(dock: DockAX, directory: AppDirectory) {
        self.dock = dock
        self.directory = directory
    }

    /// Returns true to swallow the event: every scroll over the icon of a
    /// running, not excluded app belongs to Revzen.
    func handle(_ event: CGEvent) -> Bool {
        guard let item = dock.appItem(at: event.location),
            let app = dock.runningApp(for: item, in: directory),
            !directory.isExcluded(app)
        else { return false }
        // Momentum after the fingers leave the trackpad would keep cycling.
        guard event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0 else { return true }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let delta =
            continuous
            ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            : Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let step = state.withLock { state in
            if state.pid != app.pid {
                state.stepper.reset()
                state.pid = app.pid
            }
            return state.stepper.add(delta, continuous: continuous)
        }
        if step != 0 {
            DebugLog.event(.scroll, "\(app.logName): delta=\(delta) continuous=\(continuous) -> step \(step)")
            enqueue(step, for: app.pid)
        }
        return true
    }

    private func enqueue(_ step: Int, for pid: pid_t) {
        guard state.withLock({ $0.pending.add(step, for: pid) }) else { return }
        actions.async { [self] in
            guard let cycle = state.withLock({ $0.pending.take() }) else { return }
            WindowService.cycle(cycle.target, step: cycle.step)
        }
    }
}
