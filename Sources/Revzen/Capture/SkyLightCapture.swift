import CoreGraphics
import Foundation

/// Reads a window image from the window server with the private SkyLight
/// call `CGSHWCaptureWindowList`. Unlike ScreenCaptureKit, it also returns
/// the last image of a minimized window. AltTab uses the same call.
///
/// The symbols are looked up at run time, so a macOS update that removes
/// them does not stop Revzen from launching: `image(of:)` then returns nil
/// and the preview uses the cached image or the app icon.
enum SkyLightCapture {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CaptureWindowList =
        @convention(c) (
            Int32, UnsafeMutablePointer<CGWindowID>, Int, UInt32
        ) -> Unmanaged<CFArray>?

    /// C function pointers into a system framework, immutable after lookup.
    private struct Functions: @unchecked Sendable {
        let connection: MainConnectionID
        let capture: CaptureWindowList
    }

    /// ignoreGlobalClipShape (1 << 11) and nominalResolution (1 << 9): the
    /// whole window at one pixel per point.
    private static let options: UInt32 = (1 << 11) | (1 << 9)

    private static let functions: Functions? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
            let connection = dlsym(handle, "CGSMainConnectionID"),
            let capture = dlsym(handle, "CGSHWCaptureWindowList")
        else {
            DebugLog.error(.capture, "SkyLight window capture is not available, minimized windows use the cache")
            return nil
        }
        return Functions(
            connection: unsafeBitCast(connection, to: MainConnectionID.self),
            capture: unsafeBitCast(capture, to: CaptureWindowList.self)
        )
    }()

    static func image(of id: CGWindowID) -> CGImage? {
        guard let functions else { return nil }
        var id = id
        let images = functions.capture(functions.connection(), &id, 1, options)?.takeRetainedValue() as? [CGImage]
        return images?.first
    }
}
