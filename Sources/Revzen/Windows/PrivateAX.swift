import ApplicationServices
import CoreGraphics
import Foundation

// Private HIServices SPI. No public API maps an AX window to its
// CGWindowID, which ScreenCaptureKit needs, or reaches a window on another
// Space. AltTab and DockDoor use the same calls. A macOS update can remove
// them; windowID() and remote(pid:elementID:) then return nil, the preview
// falls back to the app icon and shows only the current Space.
@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func axUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

extension AXElement {
    func windowID() -> CGWindowID? {
        var id = CGWindowID(0)
        guard axUIElementGetWindow(raw, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// The element with `elementID` inside the app `pid`. The token layout is
    /// pid (4 bytes), zero (4 bytes), the "coco" marker (4 bytes) and the
    /// element ID (8 bytes), all little-endian.
    static func remote(pid: pid_t, elementID: UInt64) -> AXElement? {
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: pid.littleEndian, toByteOffset: 0, as: Int32.self)
            bytes.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            bytes.storeBytes(of: Int32(0x636f_636f).littleEndian, toByteOffset: 8, as: Int32.self)
            bytes.storeBytes(of: elementID.littleEndian, toByteOffset: 12, as: UInt64.self)
        }
        guard let element = axUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { return nil }
        return AXElement(element)
    }
}
