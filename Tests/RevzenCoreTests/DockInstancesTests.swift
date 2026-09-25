import Testing

@testable import RevzenCore

@Suite("DockInstances")
struct DockInstancesTests {
    /// Dock icons by bundle URL: Finder, two Chrome copies around Mail, a folder.
    private let dock: [String?] = ["finder", "chrome", "mail", "chrome", nil]

    @Test("Each icon of an app launched twice gets its own copy number")
    func iconIndex() {
        #expect(DockInstances.index(of: 1, in: dock) == 0)
        #expect(DockInstances.index(of: 3, in: dock) == 1)
        #expect(DockInstances.index(of: 2, in: dock) == 0)
        #expect(DockInstances.index(of: 4, in: dock) == nil)
        #expect(DockInstances.index(of: 9, in: dock) == nil)
    }

    @Test("The n-th icon picks the n-th running copy in launch order")
    func copyForIcon() {
        let chrome = [19_902, 78_894]
        #expect(DockInstances.copy(chrome, index: 0) == 19_902)
        #expect(DockInstances.copy(chrome, index: 1) == 78_894)
    }

    @Test("A single copy needs no index, and an unknown or extra icon picks nothing")
    func edgeCases() {
        #expect(DockInstances.copy([42], index: nil) == 42)
        #expect(DockInstances.copy([19_902, 78_894], index: nil) == nil)
        #expect(DockInstances.copy([19_902, 78_894], index: 2) == nil)
        #expect(DockInstances.copy([Int](), index: 0) == nil)
    }
}
