import AppKit
import RevzenCore

/// Keeps the last image of each window. ScreenCaptureKit cannot capture a
/// minimized window; SkyLight usually can, and when it cannot, the preview
/// shows the image taken before the minimize. Images are taken:
/// - whenever a preview captures live windows,
/// - right before Revzen minimizes an app's windows,
/// - of the focused window when an app stops being the active app,
/// - of the focused window of the active app every `refreshInterval`,
///   which covers a minimize through the window's own button.
///
/// The last two take only the focused window, because the title bar button
/// minimizes that window, and capturing every window of an app with many
/// windows costs about 50 ms of capture work per window.
@MainActor
final class WindowSnapshotter {
    static let capacity = 48
    static let refreshInterval: Duration = .seconds(10)

    private let capture = CaptureService()
    private let directory: AppDirectory
    private var cache = LRUCache<CGWindowID, CGImage>(capacity: capacity)
    private var refreshTask: Task<Void, Never>?
    private var deactivationToken: NSObjectProtocol?

    init(directory: AppDirectory) {
        self.directory = directory
    }

    func start() {
        deactivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            DebugLog.event(.capture, "snapshot on deactivation of \(app.logName)")
            Task { @MainActor in await self?.snapshotFocused(pid: pid) }
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return  // cancelled by stop()
                }
                guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { continue }
                await self?.snapshotFocused(pid: pid)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if let deactivationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(deactivationToken)
        }
        deactivationToken = nil
    }

    /// Cached images for the given windows.
    func cachedImages(for ids: [CGWindowID]) -> [CGWindowID: CGImage] {
        var images: [CGWindowID: CGImage] = [:]
        for id in ids {
            images[id] = cache.value(for: id)
        }
        return images
    }

    /// Captures the windows and stores the images. `onImage` receives each
    /// visible window's image as soon as it is captured.
    func captureLive(
        _ windows: [PreviewWindow], scale: CGFloat,
        onImage: @escaping @MainActor @Sendable (CGWindowID, CGImage) -> Void = { _, _ in }
    ) async -> [CGWindowID: CGImage] {
        let size = PreviewLayout.maxImageSize
        let visible = windows.filter { !$0.window.isMinimized }.compactMap(\.windowID)
        let minimized = windows.filter(\.window.isMinimized).compactMap(\.windowID)
        var images = await capture.capture(visible, maxPointSize: size, scale: scale) { id, image in
            await onImage(id, image)
        }
        if !Task.isCancelled {
            images.merge(await capture.captureMinimized(minimized, maxPointSize: size, scale: scale)) { live, _ in live }
        }
        for (id, image) in images {
            cache.insert(image, for: id)
        }
        return images
    }

    /// Captures one visible window of the app. Excluded apps, apps without a
    /// Dock icon and Revzen itself are skipped.
    func snapshot(_ element: AXElement, pid: pid_t) async {
        await snapshot(pid: pid) {
            WindowService.previewWindow(AppWindow(element: element, pid: pid, isMinimized: false))
        }
    }

    /// Captures the focused window of the app, with the same skips.
    func snapshotFocused(pid: pid_t) async {
        await snapshot(pid: pid) { WindowService.focusedPreviewWindow(of: pid) }
    }

    /// `window` reads AX, so it runs off the main actor.
    private func snapshot(pid: pid_t, window: @escaping @Sendable () -> PreviewWindow?) async {
        guard pid != ProcessInfo.processInfo.processIdentifier, !isSkipped(pid),
            let window = await Task.detached(operation: window).value
        else { return }
        _ = await captureLive([window], scale: NSScreen.screens.first?.backingScaleFactor ?? 1)
    }

    func forget(_ id: CGWindowID) {
        cache.removeValue(for: id)
    }

    private func isSkipped(_ pid: pid_t) -> Bool {
        guard let app = directory.app(pid: pid) else { return true }
        return directory.isExcluded(app)
    }
}
