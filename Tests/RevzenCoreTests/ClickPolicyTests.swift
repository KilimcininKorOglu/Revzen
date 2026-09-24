import Testing
@testable import RevzenCore

@Suite("ClickPolicy")
struct ClickPolicyTests {
    @Test("Clicking the active app with visible windows minimizes them, like the Windows taskbar")
    func frontmostWithVisibleWindowsMinimizes() {
        let state = AppWindowState(isFrontmost: true, visibleCount: 2, minimizedCount: 1)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .minimizeAll)
    }

    @Test("A background app with visible windows is left to the Dock, which activates it")
    func backgroundWithVisibleWindowsPassesThrough() {
        let state = AppWindowState(isFrontmost: false, visibleCount: 1, minimizedCount: 0)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .passThrough)
    }

    @Test(
        "An app whose windows are all minimized gets every window back, not only one",
        arguments: [true, false]
    )
    func allMinimizedRestoresAll(isFrontmost: Bool) {
        let state = AppWindowState(isFrontmost: isFrontmost, visibleCount: 0, minimizedCount: 3)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .restoreAll)
    }

    @Test("An app without windows is left to the Dock, which opens a new window")
    func noWindowsPassesThrough() {
        let state = AppWindowState(isFrontmost: true, visibleCount: 0, minimizedCount: 0)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .passThrough)
    }

    @Test("An excluded app keeps the default Dock behavior in every state")
    func excludedAlwaysPassesThrough() {
        let states = [
            AppWindowState(isFrontmost: true, visibleCount: 2, minimizedCount: 0),
            AppWindowState(isFrontmost: false, visibleCount: 0, minimizedCount: 2)
        ]
        for state in states {
            #expect(ClickPolicy.action(for: state, isExcluded: true) == .passThrough)
        }
    }
}
