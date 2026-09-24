import Testing
@testable import RevzenCore

@Suite("ClickPolicy")
struct ClickPolicyTests {
    @Test("Clicking the active app minimizes its focused window, like the Windows taskbar")
    func frontmostWithFocusedWindowMinimizes() {
        let state = AppWindowState(isFrontmost: true, hasFocusedWindow: true)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .minimizeFocused)
    }

    @Test("A background app is left to the Dock, which activates it")
    func backgroundPassesThrough() {
        let state = AppWindowState(isFrontmost: false, hasFocusedWindow: true)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .passThrough)
    }

    @Test("An active app without a visible focused window is left to the Dock, which restores the last minimized window")
    func noFocusedWindowPassesThrough() {
        let state = AppWindowState(isFrontmost: true, hasFocusedWindow: false)
        #expect(ClickPolicy.action(for: state, isExcluded: false) == .passThrough)
    }

    @Test("An excluded app keeps the default Dock behavior")
    func excludedPassesThrough() {
        let state = AppWindowState(isFrontmost: true, hasFocusedWindow: true)
        #expect(ClickPolicy.action(for: state, isExcluded: true) == .passThrough)
    }
}
