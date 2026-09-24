import ApplicationServices

/// Reports the Dock icon under the pointer. The Dock marks the hovered icon
/// as the selected child of its icon list and posts
/// `kAXSelectedChildrenChangedNotification` on each change.
@MainActor
final class DockHoverObserver {
    private let dock: DockAX
    private let onHover: @MainActor (DockItem?) -> Void
    private var observer: AXObserver?
    private var list: AXElement?

    init(dock: DockAX, onHover: @escaping @MainActor (DockItem?) -> Void) {
        self.dock = dock
        self.onHover = onHover
    }

    /// Registers with the current Dock process. Call again after the Dock relaunches.
    func start() {
        stop()
        guard let pid = dock.pid, let list = dock.iconList() else {
            DebugLog.error(.hover, "the Dock icon list is not available, hover previews are off")
            return
        }
        var created: AXObserver?
        guard AXObserverCreate(pid, dockHoverCallback, &created) == .success, let created else {
            DebugLog.error(.hover, "creating the Dock AX observer failed")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(created, list.raw, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard result == .success else {
            DebugLog.error(.hover, "observing Dock hover failed: AXError \(result.rawValue)")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        self.list = list
        DebugLog.event(.hover, "observing Dock hover, pid \(pid)")
    }

    func stop() {
        if let observer, let list {
            AXObserverRemoveNotification(observer, list.raw, kAXSelectedChildrenChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        list = nil
    }

    fileprivate func selectionChanged() {
        let hovered = list?.elements(kAXSelectedChildrenAttribute).first.flatMap(DockAX.appItem(from:))
        DebugLog.event(.hover, "Dock selection: \(hovered?.logName ?? "none")")
        onHover(hovered)
    }
}

private func dockHoverCallback(
    observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?
) {
    // A raw pointer is not Sendable. Its bit pattern crosses into the main
    // actor closure instead; the run loop source is on the main run loop.
    let bits = UInt(bitPattern: refcon)
    MainActor.assumeIsolated {
        guard let refcon = UnsafeMutableRawPointer(bitPattern: bits) else { return }
        Unmanaged<DockHoverObserver>.fromOpaque(refcon).takeUnretainedValue().selectionChanged()
    }
}
