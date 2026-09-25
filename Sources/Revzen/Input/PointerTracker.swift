import CoreGraphics
import Dispatch
import Synchronization

/// Forwards pointer moves from the event tap thread to the main actor while
/// a preview needs them. NSEvent global monitors would need the Input
/// Monitoring permission; the event tap already has the events.
final class PointerTracker: Sendable {
    private let isActive = Atomic<Bool>(false)
    private let isDeliveryQueued = Atomic<Bool>(false)
    private let latest = Mutex<CGPoint>(.zero)
    /// The shown preview panel in top-left global coordinates.
    private let panelFrame = Mutex<CGRect?>(nil)
    private let onMove: @MainActor @Sendable (CGPoint) -> Void

    init(onMove: @escaping @MainActor @Sendable (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func setActive(_ active: Bool) {
        if isActive.exchange(active, ordering: .relaxed) != active {
            DebugLog.event(.pointer, "tracking \(active ? "on" : "off")")
        }
    }

    func setPanelFrame(_ frame: CGRect?) {
        panelFrame.withLock { $0 = frame }
    }

    /// Called on the event tap thread for a pointer move. Returns true when
    /// the move is over the preview panel: the panel never activates, so
    /// the window server sends the move to the active app under it, which
    /// reacts to the pointer it cannot see. The move goes to Revzen only.
    func keepsOverPanel(_ event: CGEvent) -> Bool {
        guard panelFrame.withLock({ $0?.contains(event.location) }) == true else { return false }
        event.postToPid(getpid())
        return true
    }

    /// Called on the event tap thread for every pointer move. Moves that
    /// arrive before the main actor reads the last one are coalesced.
    func moved(to point: CGPoint) {
        guard isActive.load(ordering: .relaxed) else { return }
        latest.withLock { $0 = point }
        guard !isDeliveryQueued.exchange(true, ordering: .acquiringAndReleasing) else { return }
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                isDeliveryQueued.store(false, ordering: .releasing)
                onMove(latest.withLock { $0 })
            }
        }
    }
}
