import CoreGraphics

/// The screen edge that holds the Dock.
public enum DockEdge: Sendable, Equatable {
    case bottom, left, right

    /// Derives the edge from the frame of the Dock's icon list. A wide list
    /// sits at the bottom. A tall list sits on the side it is closer to.
    public static func detect(listFrame: CGRect, screen: CGRect) -> DockEdge {
        if listFrame.width >= listFrame.height {
            return .bottom
        }
        return listFrame.midX < screen.midX ? .left : .right
    }

    public var isVertical: Bool { self != .bottom }

    /// The largest magnified icon the Dock draws, in points.
    public static let maxMagnifiedIcon: CGFloat = 128

    /// The strip of `screen` along the Dock edge that can hold a Dock icon:
    /// the whole screen length, from the screen edge to past the icon list
    /// by twice its thickness and at least one magnified icon. A point
    /// outside it is not on a Dock icon.
    public static func band(listFrame: CGRect, screen: CGRect) -> CGRect {
        let edge = detect(listFrame: listFrame, screen: screen)
        let thickness = edge.isVertical ? listFrame.width : listFrame.height
        let reach = max(2 * thickness, maxMagnifiedIcon)
        switch edge {
        case .bottom:
            let top = max(screen.minY, listFrame.minY - reach)
            return CGRect(x: screen.minX, y: top, width: screen.width, height: screen.maxY - top)
        case .left:
            let right = min(screen.maxX, listFrame.maxX + reach)
            return CGRect(x: screen.minX, y: screen.minY, width: right - screen.minX, height: screen.height)
        case .right:
            let left = max(screen.minX, listFrame.minX - reach)
            return CGRect(x: left, y: screen.minY, width: screen.maxX - left, height: screen.height)
        }
    }
}

/// Positions the preview panel next to a Dock icon.
///
/// Every rectangle uses global display coordinates with the origin at the
/// top-left of the primary display, the space of `CGEvent` and AX frames.
public enum PanelPlacement {
    public static let gap: CGFloat = 8
    public static let margin: CGFloat = 4

    public static func frame(panelSize: CGSize, anchor: CGRect, edge: DockEdge, screen: CGRect) -> CGRect {
        var origin: CGPoint
        switch edge {
        case .bottom:
            origin = CGPoint(x: anchor.midX - panelSize.width / 2, y: anchor.minY - gap - panelSize.height)
        case .left:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - panelSize.height / 2)
        case .right:
            origin = CGPoint(x: anchor.minX - gap - panelSize.width, y: anchor.midY - panelSize.height / 2)
        }
        origin.x = clamp(origin.x, low: screen.minX + margin, high: screen.maxX - margin - panelSize.width)
        origin.y = clamp(origin.y, low: screen.minY + margin, high: screen.maxY - margin - panelSize.height)
        return CGRect(origin: origin, size: panelSize)
    }

    /// Converts between the top-left global space and the bottom-left space
    /// of AppKit. The conversion is its own inverse.
    public static func flipped(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// A panel larger than the screen keeps its leading edge on screen.
    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        max(low, min(value, high))
    }
}
