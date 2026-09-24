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
    private let onMove: @MainActor @Sendable (CGPoint) -> Void

    init(onMove: @escaping @MainActor @Sendable (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func setActive(_ active: Bool) {
        if isActive.exchange(active, ordering: .relaxed) != active {
            DebugLog.event(.pointer, "tracking \(active ? "on" : "off")")
        }
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
