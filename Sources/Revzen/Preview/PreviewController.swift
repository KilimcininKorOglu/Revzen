import AppKit
import RevzenCore

/// Shows the window preview for the hovered Dock icon and hides it when the
/// pointer leaves both the icon and the panel.
@MainActor
final class PreviewController {
    private let dock: DockAX
    private let directory: AppDirectory
    private let capture = CaptureService()
    private let hoverDelay: @MainActor () -> Duration
    private let model = PreviewModel()
    private lazy var panel = PreviewPanel(model: model)
    private lazy var hover = DockHoverObserver(dock: dock) { [weak self] item in self?.hoverChanged(item) }

    /// Receives pointer moves from the event tap while a preview is pending or shown.
    private(set) lazy var pointer = PointerTracker { [weak self] point in self?.pointerMoved(to: point) }

    /// The icon the pending or shown preview belongs to.
    private var anchor: DockItem?
    private var pending: Task<Void, Never>?

    init(dock: DockAX, directory: AppDirectory, hoverDelay: @escaping @MainActor () -> Duration) {
        self.dock = dock
        self.directory = directory
        self.hoverDelay = hoverDelay
        model.onSelect = { [weak self] window in self?.select(window) }
        model.onClose = { [weak self] window in self?.close(window) }
    }

    func start() {
        hover.start()
    }

    /// Re-registers the hover observer with a relaunched Dock.
    func dockRelaunched() {
        hide()
        hover.start()
    }

    func stop() {
        hover.stop()
        hide()
    }

    private func hoverChanged(_ item: DockItem?) {
        pending?.cancel()
        guard let item, let app = directory.app(forBundleURL: item.appURL), !directory.isExcluded(app) else {
            // The pointer may be on its way into the panel. pointerMoved decides.
            return
        }
        guard item != anchor || !panel.isVisible else { return }
        // Moving between icons with the panel open switches at once, as on Windows.
        let delay = panel.isVisible ? .zero : hoverDelay()
        anchor = item
        pointer.setActive(true)
        pending = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // cancelled by a newer hover
            }
            await self?.show(app, for: item)
        }
    }

    private func show(_ app: RunningApp, for item: DockItem) async {
        let pid = app.pid
        let windows = await Task.detached { WindowService.previewWindows(of: pid) }.value
        guard !Task.isCancelled else { return }
        guard !windows.isEmpty, let screen = Self.screen(containing: item.frame) else {
            hide()
            return
        }
        let edge = dock.iconList()?.frame().map { DockEdge.detect(listFrame: $0, screen: screen.cgFrame) } ?? .bottom
        let layout = PreviewLayout(
            count: windows.count,
            edge: edge,
            available: edge.isVertical ? screen.cgFrame.height : screen.cgFrame.width
        )
        // Images of windows that are still listed stay until the new capture
        // arrives, so a refresh after a close does not flicker.
        let ids = Set(windows.compactMap(\.windowID))
        model.images = model.images.filter { ids.contains($0.key) }
        model.windows = windows
        model.edge = edge
        model.layout = layout
        model.appIcon = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
        place(layout.panelSize, anchor: item, edge: edge, screen: screen)
        panel.orderFrontRegardless()
        await loadImages(for: windows, scale: screen.backingScaleFactor)
    }

    private func loadImages(for windows: [PreviewWindow], scale: CGFloat) async {
        let ids = windows.filter { !$0.window.isMinimized }.compactMap(\.windowID)
        let images = await capture.capture(ids, maxPointSize: PreviewLayout.maxImageSize, scale: scale)
        guard !Task.isCancelled, model.windows == windows else { return }
        model.images.merge(images) { _, new in new }
    }

    private func place(_ size: CGSize, anchor: DockItem, edge: DockEdge, screen: NSScreen) {
        let frame = PanelPlacement.frame(panelSize: size, anchor: anchor.frame, edge: edge, screen: screen.cgFrame)
        panel.setFrame(PanelPlacement.flipped(frame, primaryScreenHeight: NSScreen.primaryHeight), display: true)
    }

    private func select(_ window: PreviewWindow) {
        hide()
        Task.detached { WindowService.focus(window.window) }
    }

    /// Closes the window, then lists the app's windows again. The list is
    /// read back instead of edited, because the app can refuse the close,
    /// for example with a save dialog.
    private func close(_ window: PreviewWindow) {
        guard let anchor, let app = directory.app(forBundleURL: anchor.appURL) else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            await Task.detached { WindowService.close(window.window) }.value
            do {
                // The app removes the window from its AX list shortly after the press.
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await self?.show(app, for: anchor)
        }
    }

    /// `point` is in top-left global coordinates, as the event tap reports it.
    private func pointerMoved(to point: CGPoint) {
        guard let anchor else { return }
        let panelFrame = PanelPlacement.flipped(panel.frame, primaryScreenHeight: NSScreen.primaryHeight)
        // The union also covers the gap between the icon and the panel.
        let region = panel.isVisible ? anchor.frame.union(panelFrame) : anchor.frame
        if !region.insetBy(dx: -2, dy: -2).contains(point) {
            hide()
        }
    }

    private func hide() {
        pending?.cancel()
        pending = nil
        anchor = nil
        pointer.setActive(false)
        panel.orderOut(nil)
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.cgFrame.contains(center) }
    }
}

extension NSScreen {
    /// Height of the screen that holds the menu bar, the origin of both
    /// coordinate spaces.
    static var primaryHeight: CGFloat {
        screens.first?.frame.height ?? 0
    }

    /// The screen frame in top-left global coordinates.
    var cgFrame: CGRect {
        PanelPlacement.flipped(frame, primaryScreenHeight: Self.primaryHeight)
    }
}
