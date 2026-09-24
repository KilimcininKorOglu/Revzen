import CoreGraphics
import ScreenCaptureKit

/// Captures single-window images with ScreenCaptureKit.
actor CaptureService {
    /// Captures each window that is on screen, scaled to fit `maxPointSize`
    /// at `scale` pixels per point. Windows that ScreenCaptureKit does not
    /// list, such as minimized ones, are missing from the result.
    func capture(_ ids: [CGWindowID], maxPointSize: CGSize, scale: CGFloat) async -> [CGWindowID: CGImage] {
        guard CGPreflightScreenCaptureAccess(), !ids.isEmpty else { return [:] }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            log.error("listing shareable windows failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        let wanted = Set(ids)
        var images: [CGWindowID: CGImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) && window.isOnScreen {
            if let image = await capture(window, maxPointSize: maxPointSize, scale: scale) {
                images[window.windowID] = image
            }
        }
        return images
    }

    private func capture(_ window: SCWindow, maxPointSize: CGSize, scale: CGFloat) async -> CGImage? {
        let config = SCStreamConfiguration()
        let fit = Self.aspectFit(window.frame.size, into: maxPointSize)
        config.width = Int(fit.width * scale)
        config.height = Int(fit.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            )
        } catch {
            log.error("capture of window \(window.windowID) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func aspectFit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let ratio = min(box.width / size.width, box.height / size.height)
        return CGSize(width: max(1, size.width * ratio), height: max(1, size.height * ratio))
    }
}
