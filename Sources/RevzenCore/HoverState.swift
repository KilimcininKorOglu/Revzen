/// Which Dock icon the pointer is over, as far as the preview is concerned.
///
/// The Dock posts its selection-changed notification when the pointer enters
/// an icon and again when the pointer leaves the Dock, and the selection
/// still names the last icon in both cases. The pointer position tells the
/// two apart. Inside the Dock, the Dock posts nothing when the pointer
/// leaves an icon for the gap below or beside it and comes back, so a return
/// to the same icon comes from pointer tracking instead.
public struct HoverState<Item: Equatable & Sendable>: Sendable {
    /// The icon the pointer is over, or last left without leaving the Dock.
    public private(set) var hovered: Item?
    /// The icon whose Dock menu opened. It gets no preview until the pointer
    /// moves to another icon or leaves the Dock.
    private var suppressed: Item?

    public init() {}

    /// Handles a Dock notification. Returns the icon to preview, if any.
    public mutating func dockNotified(_ item: Item?, pointerInside: Bool) -> Item? {
        guard let item, pointerInside else {
            // The pointer left the Dock.
            hovered = nil
            suppressed = nil
            return nil
        }
        if item != suppressed {
            suppressed = nil
        }
        hovered = item
        return suppressed == nil ? item : nil
    }

    /// The pointer came back to the hovered icon without a Dock notification.
    /// Returns the icon to preview, if any.
    public func pointerReturned() -> Item? {
        suppressed == nil ? hovered : nil
    }

    /// The Dock menu of the hovered icon opened, for example by a right click.
    public mutating func menuOpened() {
        suppressed = hovered
    }
}
