import Foundation

/// The order of the windows in the preview.
public enum WindowOrder {
    /// Sorts by title as Finder does: case-insensitive, with numbers compared
    /// by value, so "Doc 2" comes before "Doc 10". Untitled windows come
    /// last. Equal titles keep the creation order (ascending window ID), so
    /// the order does not change between two previews.
    public static func alphabetical<Item>(
        _ items: [Item],
        title: (Item) -> String,
        windowID: (Item) -> UInt32?
    ) -> [Item] {
        items.sorted { lhs, rhs in
            let (left, right) = (title(lhs), title(rhs))
            if left.isEmpty != right.isEmpty {
                return right.isEmpty
            }
            switch left.localizedStandardCompare(right) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return (windowID(lhs) ?? .max) < (windowID(rhs) ?? .max)
            }
        }
    }
}
