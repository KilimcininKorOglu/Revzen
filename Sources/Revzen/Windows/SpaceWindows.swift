import ApplicationServices
import CoreGraphics
import Foundation
import RevzenCore

/// Finds the AX elements of an app's windows on other Spaces.
///
/// `kAXWindowsAttribute` lists only the current Space. The window server
/// still knows the other windows, and every AX element of an app has a
/// numeric element ID. A remote token built from the pid and an element ID
/// yields the element, so a scan over the low IDs finds the window elements.
/// AltTab uses the same technique.
enum SpaceWindows {
    static let maxElementID: UInt64 = 1000
    /// A hung app would make the scan wait on every ID; the deadline bounds it.
    static let scanDeadline: TimeInterval = 0.5

    static func windows(of pid: pid_t, known: Set<CGWindowID>) -> [AppWindow] {
        var wanted = SpaceFilter.otherSpaceCandidates(in: windowList(), pid: pid, known: known)
        guard !wanted.isEmpty else { return [] }
        var found: [AppWindow] = []
        let deadline = Date().addingTimeInterval(scanDeadline)
        for elementID in 0..<maxElementID where Date() < deadline {
            guard let element = AXElement.remote(pid: pid, elementID: elementID),
                  element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  let id = element.windowID(), wanted.remove(id) != nil else { continue }
            found.append(AppWindow(element: element, pid: pid, isMinimized: false))
            if wanted.isEmpty { break }
        }
        return found
    }

    private static func windowList() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            log.error("the window server returned no window list")
            return []
        }
        return list.compactMap(info)
    }

    private static func info(_ entry: [String: Any]) -> WindowInfo? {
        guard let id = entry[kCGWindowNumber as String] as? UInt32,
              let pid = entry[kCGWindowOwnerPID as String] as? Int32,
              let layer = entry[kCGWindowLayer as String] as? Int,
              let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
        let onScreen = entry[kCGWindowIsOnscreen as String] as? Bool ?? false
        return WindowInfo(id: id, ownerPID: pid, layer: layer, bounds: bounds, isOnScreen: onScreen)
    }
}
