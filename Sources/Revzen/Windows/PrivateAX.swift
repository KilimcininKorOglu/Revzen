import ApplicationServices
import CoreGraphics
import Foundation

/// Private HIServices SPI. No public API maps an AX window to its
/// CGWindowID, which ScreenCaptureKit needs, or reaches a window on another
/// Space. AltTab and DockDoor use the same calls.
///
/// The symbols are looked up at run time, so a macOS update that removes
/// them does not stop Revzen from launching: `windowID()` and
/// `remote(pid:elementID:)` then return nil, the preview falls back to the
/// app icon and shows only the current Space.
private enum PrivateAX {
    typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    /// C function pointers into a system framework, immutable after lookup.
    struct Functions: @unchecked Sendable {
        let getWindow: GetWindow?
        let createWithRemoteToken: CreateWithRemoteToken?
    }

    static let functions: Functions = {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices"
        let handle = dlopen(path, RTLD_LAZY)
        let getWindow = handle.flatMap { dlsym($0, "_AXUIElementGetWindow") }
        let createWithRemoteToken = handle.flatMap { dlsym($0, "_AXUIElementCreateWithRemoteToken") }
        if getWindow == nil {
            DebugLog.error(.window, "_AXUIElementGetWindow is not available, previews show app icons")
        }
        if createWithRemoteToken == nil {
            DebugLog.error(.window, "_AXUIElementCreateWithRemoteToken is not available, previews show the current Space")
        }
        return Functions(
            getWindow: getWindow.map { unsafeBitCast($0, to: GetWindow.self) },
            createWithRemoteToken: createWithRemoteToken.map { unsafeBitCast($0, to: CreateWithRemoteToken.self) }
        )
    }()
}

extension AXElement {
    func windowID() -> CGWindowID? {
        guard let getWindow = PrivateAX.functions.getWindow else { return nil }
        var id = CGWindowID(0)
        guard getWindow(raw, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// The element with `elementID` inside the app `pid`. The token layout is
    /// pid (4 bytes), zero (4 bytes), the "coco" marker (4 bytes) and the
    /// element ID (8 bytes), all little-endian.
    static func remote(pid: pid_t, elementID: UInt64) -> AXElement? {
        guard let create = PrivateAX.functions.createWithRemoteToken else { return nil }
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid.littleEndian, toByteOffset: 0, as: Int32.self)
            bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            bytes.storeBytes(of: Int32(0x636f_636f).littleEndian, toByteOffset: 8, as: Int32.self)
            bytes.storeBytes(of: elementID.littleEndian, toByteOffset: 12, as: UInt64.self)
        }
        guard let element = create(token as CFData)?.takeRetainedValue() else { return nil }
        return AXElement(element)
    }
}
