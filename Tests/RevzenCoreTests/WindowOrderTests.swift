import Testing
@testable import RevzenCore

@Suite("WindowOrder")
struct WindowOrderTests {
    private struct Window: Equatable {
        let title: String
        let id: UInt32?
    }

    private func titles(_ windows: [Window]) -> [String] {
        WindowOrder.alphabetical(windows, title: \.title, windowID: \.id).map(\.title)
    }

    @Test("Windows are listed by title, whatever the creation order")
    func alphabetical() {
        let windows = [Window(title: "Notes", id: 1), Window(title: "Budget", id: 2), Window(title: "Mail", id: 3)]
        #expect(titles(windows) == ["Budget", "Mail", "Notes"])
    }

    @Test("Case does not matter and numbers compare by value, as in Finder")
    func finderRules() {
        let windows = [Window(title: "doc 10", id: 1), Window(title: "Doc 2", id: 2), Window(title: "apple", id: 3)]
        #expect(titles(windows) == ["apple", "Doc 2", "doc 10"])
    }

    @Test("Untitled windows come after the titled ones")
    func untitledLast() {
        let windows = [Window(title: "", id: 1), Window(title: "Zeta", id: 2), Window(title: "Alpha", id: 3)]
        #expect(titles(windows) == ["Alpha", "Zeta", ""])
    }

    @Test("Equal titles keep the creation order, so two previews match")
    func stableForEqualTitles() {
        let windows = [
            Window(title: "Untitled", id: 30), Window(title: "Untitled", id: nil), Window(title: "Untitled", id: 10)
        ]
        let ordered = WindowOrder.alphabetical(windows, title: \.title, windowID: \.id)
        #expect(ordered.map(\.id) == [10, 30, nil])
    }
}
