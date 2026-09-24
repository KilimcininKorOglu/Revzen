import CoreGraphics
import Testing
@testable import RevzenCore

@Suite("PanelPlacement")
struct PanelPlacementTests {
    private let screen = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    private let size = CGSize(width: 400, height: 180)

    @Test("A bottom Dock gets the panel centered above the icon")
    func bottomCentersAboveIcon() {
        let icon = CGRect(x: 980, y: 1140, width: 40, height: 50)
        let frame = PanelPlacement.frame(panelSize: size, anchor: icon, edge: .bottom, screen: screen)
        #expect(frame.midX == icon.midX)
        #expect(frame.maxY == icon.minY - PanelPlacement.gap)
    }

    @Test("Side Docks get the panel beside the icon, on the screen side")
    func sidesPlaceBesideIcon() {
        let left = CGRect(x: 0, y: 580, width: 50, height: 40)
        let right = CGRect(x: 1950, y: 580, width: 50, height: 40)
        let leftFrame = PanelPlacement.frame(panelSize: size, anchor: left, edge: .left, screen: screen)
        let rightFrame = PanelPlacement.frame(panelSize: size, anchor: right, edge: .right, screen: screen)
        #expect(leftFrame.minX == left.maxX + PanelPlacement.gap)
        #expect(rightFrame.maxX == right.minX - PanelPlacement.gap)
        #expect(leftFrame.midY == left.midY)
    }

    @Test("An icon near a screen corner keeps the whole panel on screen")
    func cornerIconStaysOnScreen() {
        let icon = CGRect(x: 5, y: 1140, width: 40, height: 50)
        let frame = PanelPlacement.frame(panelSize: size, anchor: icon, edge: .bottom, screen: screen)
        #expect(frame.minX == screen.minX + PanelPlacement.margin)
        #expect(screen.contains(frame))
    }

    @Test("A secondary display with a negative origin is respected")
    func secondaryDisplay() {
        let secondary = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let icon = CGRect(x: -1430, y: 850, width: 40, height: 50)
        let frame = PanelPlacement.frame(panelSize: size, anchor: icon, edge: .bottom, screen: secondary)
        #expect(secondary.contains(frame))
    }

    @Test("Flipping between the CG and AppKit spaces is its own inverse")
    func flipRoundTrip() {
        let rect = CGRect(x: 100, y: 50, width: 300, height: 200)
        let flipped = PanelPlacement.flipped(rect, primaryScreenHeight: 1200)
        #expect(flipped == CGRect(x: 100, y: 950, width: 300, height: 200))
        #expect(PanelPlacement.flipped(flipped, primaryScreenHeight: 1200) == rect)
    }

    @Test("The Dock edge follows the shape and side of the icon list", arguments: [
        (CGRect(x: 500, y: 1150, width: 1000, height: 50), DockEdge.bottom),
        (CGRect(x: 0, y: 200, width: 50, height: 800), DockEdge.left),
        (CGRect(x: 1950, y: 200, width: 50, height: 800), DockEdge.right)
    ])
    func edgeDetection(list: CGRect, expected: DockEdge) {
        #expect(DockEdge.detect(listFrame: list, screen: screen) == expected)
    }
}

@Suite("PreviewLayout")
struct PreviewLayoutTests {
    @Test("A few windows get full-size tiles in a row")
    func fullSizeRow() {
        let layout = PreviewLayout(count: 3, edge: .bottom, available: 2000)
        #expect(layout.imageSize == PreviewLayout.maxImageSize)
        let expectedWidth = 2 * PreviewLayout.padding + 2 * PreviewLayout.spacing + 3 * PreviewLayout.maxImageSize.width
        #expect(layout.panelSize.width == expectedWidth)
    }

    @Test("Many windows shrink the tiles until the row fits the screen")
    func shrinksToFit() {
        let layout = PreviewLayout(count: 10, edge: .bottom, available: 1600)
        #expect(layout.panelSize.width <= 1600)
        #expect(layout.imageSize.width < PreviewLayout.maxImageSize.width)
    }

    @Test("Tiles never shrink below the minimum scale, even when the row overflows")
    func minimumScale() {
        let layout = PreviewLayout(count: 40, edge: .bottom, available: 1000)
        #expect(layout.imageSize.width == (PreviewLayout.maxImageSize.width * PreviewLayout.minScale).rounded(.down))
    }

    @Test("A side Dock stacks the tiles in a column")
    func sideDockColumn() {
        let layout = PreviewLayout(count: 2, edge: .left, available: 1200)
        #expect(layout.panelSize.height > layout.panelSize.width)
    }
}
