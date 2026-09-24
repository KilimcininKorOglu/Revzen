import CoreGraphics
import ScreenCaptureKit

/// Captures single-window images: ScreenCaptureKit for visible windows,
/// SkyLight for minimized ones.
actor CaptureService {
    /// Captures each window, scaled to fit `maxPointSize` at `scale` pixels
    /// per point. Windows on other Spaces are captured too. Windows that
    /// ScreenCaptureKit does not list are missing from the result. Callers
    /// leave minimized windows out, because their capture is empty.
    func capture(_ ids: [CGWindowID], maxPointSize: CGSize, scale: CGFloat) async -> [CGWindowID: CGImage] {
        guard CGPreflightScreenCaptureAccess(), !ids.isEmpty else { return [:] }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            DebugLog.error(.capture, "listing shareable windows failed: \(error.localizedDescription)")
            return [:]
        }
        let wanted = Set(ids)
        var images: [CGWindowID: CGImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) {
            if let image = await capture(window, maxPointSize: maxPointSize, scale: scale) {
                images[window.windowID] = image
            }
        }
        let missing = wanted.subtracting(images.keys).sorted()
        DebugLog.event(
            .capture,
            "captured \(images.count) of \(ids.count) windows"
                + (missing.isEmpty ? "" : ", no image for \(missing)"))
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
            DebugLog.error(.capture, "capture of window \(window.windowID) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func aspectFit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let ratio = min(box.width / size.width, box.height / size.height)
        return CGSize(width: max(1, size.width * ratio), height: max(1, size.height * ratio))
    }
}

extension CaptureService {
    /// Captures minimized windows. ScreenCaptureKit returns nothing for
    /// them, but the window server keeps their last image.
    func captureMinimized(_ ids: [CGWindowID], maxPointSize: CGSize, scale: CGFloat) -> [CGWindowID: CGImage] {
        guard CGPreflightScreenCaptureAccess(), !ids.isEmpty else { return [:] }
        var images: [CGWindowID: CGImage] = [:]
        for id in ids {
            guard let full = SkyLightCapture.image(of: id) else { continue }
            images[id] = Self.scaled(full, toFit: maxPointSize, scale: scale)
        }
        let missing = Set(ids).subtracting(images.keys).sorted()
        DebugLog.event(
            .capture,
            "captured \(images.count) of \(ids.count) minimized windows"
                + (missing.isEmpty ? "" : ", no image for \(missing)"))
        return images
    }

    /// The window server returns the full window; the preview needs a tile.
    private static func scaled(_ image: CGImage, toFit box: CGSize, scale: CGFloat) -> CGImage? {
        let fit = aspectFit(CGSize(width: image.width, height: image.height), into: box)
        let width = Int(fit.width * scale)
        let height = Int(fit.height * scale)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            DebugLog.error(.capture, "no bitmap context for a \(width)x\(height) preview image")
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
