import Testing

@testable import RevzenCore

@Suite("ClickPolicy")
struct ClickPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let why: String
        let state: AppWindowState
        let isExcluded: Bool
        let expected: ClickAction
        var testDescription: String { why }
    }

    static let cases: [Case] = [
        Case(
            why: "Clicking the active app minimizes its focused window, like the Windows taskbar",
            state: AppWindowState(isFrontmost: true, hasFocusedWindow: true),
            isExcluded: false, expected: .minimizeFocused
        ),
        Case(
            why: "The click after a minimize restores that window, although macOS focused another window of the app",
            state: AppWindowState(isFrontmost: true, hasFocusedWindow: true, hasClickMinimizedWindow: true),
            isExcluded: false, expected: .restoreClickMinimized
        ),
        Case(
            why: "The click after a minimize restores that window also when the app has no other window",
            state: AppWindowState(isFrontmost: true, hasFocusedWindow: false, hasClickMinimizedWindow: true),
            isExcluded: false, expected: .restoreClickMinimized
        ),
        Case(
            why: "A background app is left to the Dock, which activates it",
            state: AppWindowState(isFrontmost: false, hasFocusedWindow: true, hasClickMinimizedWindow: true),
            isExcluded: false, expected: .passThrough
        ),
        Case(
            why: "An active app without a visible focused window is left to the Dock, which restores the last minimized window",
            state: AppWindowState(isFrontmost: true, hasFocusedWindow: false),
            isExcluded: false, expected: .passThrough
        ),
        Case(
            why: "An excluded app keeps the default Dock behavior",
            state: AppWindowState(isFrontmost: true, hasFocusedWindow: true, hasClickMinimizedWindow: true),
            isExcluded: true, expected: .passThrough
        )
    ]

    @Test("A Dock click maps to the Windows taskbar behavior", arguments: cases)
    func action(_ testCase: Case) {
        #expect(ClickPolicy.action(for: testCase.state, isExcluded: testCase.isExcluded) == testCase.expected)
    }
}

@Suite("ClickMinimizeMemory")
struct ClickMinimizeMemoryTests {
    /// A memory that holds the window "editor" of pid 42, minimized at generation 3.
    private func editorMinimized() -> ClickMinimizeMemory<String> {
        var memory = ClickMinimizeMemory<String>()
        memory.record("editor", pid: 42, generation: 3)
        return memory
    }

    @Test("The memory returns the window minimized for the same app while it stays frontmost")
    func returnsWindowForSameGeneration() {
        var memory = editorMinimized()
        #expect(memory.window(of: 42, generation: 3) == "editor")
        #expect(memory.window(of: 7, generation: 3) == nil)
    }

    @Test("An activation after the click makes the next click minimize again")
    func activationInvalidatesEntry() {
        var memory = editorMinimized()
        #expect(memory.window(of: 42, generation: 4) == nil)
        // The stale entry is gone, also for the old generation.
        #expect(memory.window(of: 42, generation: 3) == nil)
    }

    @Test("A restored window is forgotten, so the click after the restore minimizes it again")
    func forgetRemovesEntry() {
        var memory = editorMinimized()
        memory.forget(42)
        #expect(memory.window(of: 42, generation: 3) == nil)
    }

    @Test("A new minimize replaces the remembered window of the app")
    func recordReplacesEntry() {
        var memory = editorMinimized()
        memory.record("terminal", pid: 42, generation: 3)
        #expect(memory.window(of: 42, generation: 3) == "terminal")
    }

    @Test("A deferred minimize runs only while its click is the latest for the window")
    func tokenOfLatestClick() {
        var memory = ClickMinimizeMemory<String>()
        let first = memory.record("editor", pid: 42, generation: 3)
        #expect(memory.isLatest(first, for: 42))
        // A second click on the same window replaces the first click.
        let second = memory.record("editor", pid: 42, generation: 3)
        #expect(!memory.isLatest(first, for: 42))
        #expect(memory.isLatest(second, for: 42))
        // The focus seen after the first click's minimize is not recorded.
        memory.recordFocusAfterMinimize("terminal", pid: 42, token: first)
        #expect(!memory.focusMoved(of: 42, focused: "browser"))
        // A restore forgets the window, so its pending minimize is dropped.
        memory.forget(42)
        #expect(!memory.isLatest(second, for: 42))
    }

    /// macOS focused `after` once the minimize of "alpha" ended ("pending":
    /// not recorded yet), and `focused` is focused at the next click.
    struct FocusCase: Sendable, CustomTestStringConvertible {
        let after: String??
        let focused: String?
        let moved: Bool
        var testDescription: String { "after \(String(describing: after)), focused \(focused ?? "none")" }
    }

    static let focusCases = [
        FocusCase(after: .none, focused: "beta", moved: false),
        FocusCase(after: "beta", focused: "beta", moved: false),
        FocusCase(after: "beta", focused: "gamma", moved: true),
        FocusCase(after: "beta", focused: nil, moved: false),
        FocusCase(after: .some(nil), focused: "new document", moved: true)
    ]

    @Test("Only a window the user focused after the minimize ends the restore", arguments: focusCases)
    func focusMoved(_ focusCase: FocusCase) {
        var memory = ClickMinimizeMemory<String>()
        let token = memory.record("alpha", pid: 42, generation: 3)
        if case .some(let after) = focusCase.after {
            memory.recordFocusAfterMinimize(after, pid: 42, token: token)
        }
        #expect(memory.focusMoved(of: 42, focused: focusCase.focused) == focusCase.moved)
    }
}
