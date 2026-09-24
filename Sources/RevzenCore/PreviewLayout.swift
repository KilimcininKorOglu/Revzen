import CoreGraphics

/// Sizes of the preview panel and of its tiles.
public struct PreviewLayout: Sendable, Equatable {
    public static let maxImageSize = CGSize(width: 220, height: 138)
    public static let minScale: CGFloat = 0.5
    public static let titleHeight: CGFloat = 20
    public static let spacing: CGFloat = 8
    public static let padding: CGFloat = 10

    /// The box for one window image. The image is aspect-fit inside it.
    public let imageSize: CGSize
    public let panelSize: CGSize

    /// Lays out `count` tiles in a row (bottom Dock) or a column (side Dock).
    /// Tiles shrink, down to `minScale`, so the panel fits in `available`,
    /// the screen length along the stacking direction.
    public init(count: Int, edge: DockEdge, available: CGFloat) {
        let count = max(count, 1)
        let full = Self.maxImageSize
        let tileLength = edge.isVertical ? full.height + Self.titleHeight : full.width
        let fixed = 2 * Self.padding + CGFloat(count - 1) * Self.spacing
        let needed = fixed + CGFloat(count) * tileLength
        let scale =
            needed <= available
            ? 1
            : max(Self.minScale, (available - fixed) / (CGFloat(count) * tileLength))

        // Rounding down keeps a shrunk row inside `available`.
        imageSize = CGSize(width: (full.width * scale).rounded(.down), height: (full.height * scale).rounded(.down))
        let tile = CGSize(width: imageSize.width, height: imageSize.height + Self.titleHeight)
        let along = fixed + CGFloat(count) * (edge.isVertical ? tile.height : tile.width)
        let across = 2 * Self.padding + (edge.isVertical ? tile.width : tile.height)
        panelSize =
            edge.isVertical
            ? CGSize(width: across, height: along)
            : CGSize(width: along, height: across)
    }
}
