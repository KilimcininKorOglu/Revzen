import CoreGraphics

/// One entry of the CoreGraphics window list.
public struct WindowInfo: Sendable, Equatable {
    public let id: UInt32
    public let ownerPID: Int32
    public let layer: Int
    public let bounds: CGRect
    public let isOnScreen: Bool

    public init(id: UInt32, ownerPID: Int32, layer: Int, bounds: CGRect, isOnScreen: Bool) {
        self.id = id
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.isOnScreen = isOnScreen
    }
}

/// Finds the windows of an app that may sit on another Space.
public enum SpaceFilter {
    /// Smaller off-screen windows are helper windows, not documents.
    public static let minimumSize = CGSize(width: 100, height: 50)

    /// The IDs of normal-layer, off-screen, document-sized windows of `pid`
    /// that the AX window list did not report. The AX list covers the
    /// current Space and minimized windows, so the rest are on other Spaces.
    public static func otherSpaceCandidates(in list: [WindowInfo], pid: Int32, known: Set<UInt32>) -> Set<UInt32> {
        Set(list.lazy.filter { info in
            info.ownerPID == pid
                && info.layer == 0
                && !info.isOnScreen
                && info.bounds.width >= minimumSize.width
                && info.bounds.height >= minimumSize.height
                && !known.contains(info.id)
        }.map(\.id))
    }
}
