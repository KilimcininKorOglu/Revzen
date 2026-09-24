import ApplicationServices
import CoreGraphics

// Private HIServices SPI. No public API maps an AX window to its
// CGWindowID, which ScreenCaptureKit needs. AltTab and DockDoor use the same
// call. A macOS update can remove it; windowID() then returns nil and the
// preview falls back to the app icon.
@_silgen_name("_AXUIElementGetWindow")
private func axUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXElement {
    func windowID() -> CGWindowID? {
        var id = CGWindowID(0)
        guard axUIElementGetWindow(raw, &id) == .success, id != 0 else { return nil }
        return id
    }
}
