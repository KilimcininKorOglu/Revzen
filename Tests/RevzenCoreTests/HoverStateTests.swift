import Testing
@testable import RevzenCore

@Suite("HoverState")
struct HoverStateTests {
    @Test("Entering an icon previews it")
    func enterPreviews() {
        var state = HoverState<String>()
        #expect(state.dockNotified("TextEdit", pointerInside: true) == "TextEdit")
    }

    @Test("The notification sent when the pointer leaves the Dock does not preview the last icon")
    func leavingDockDoesNotPreview() {
        var state = HoverState<String>()
        _ = state.dockNotified("TextEdit", pointerInside: true)
        #expect(state.dockNotified("TextEdit", pointerInside: false) == nil)
        #expect(state.hovered == nil)
    }

    @Test("Returning to the same icon from the gap inside the Dock previews it again")
    func returnInsideDockPreviews() {
        var state = HoverState<String>()
        _ = state.dockNotified("TextEdit", pointerInside: true)
        #expect(state.pointerReturned() == "TextEdit")
    }

    @Test("After the Dock menu opens, the icon gets no preview until the pointer moves on")
    func menuSuppressesUntilAnotherIcon() {
        var state = HoverState<String>()
        _ = state.dockNotified("TextEdit", pointerInside: true)
        state.menuOpened()
        #expect(state.pointerReturned() == nil)
        #expect(state.dockNotified("TextEdit", pointerInside: true) == nil)
        #expect(state.dockNotified("Finder", pointerInside: true) == "Finder")
        #expect(state.dockNotified("TextEdit", pointerInside: true) == "TextEdit")
    }

    @Test("The cleared selection of an opening menu keeps the icon suppressed when the menu closes")
    func menuSelectionClearKeepsSuppression() {
        var state = HoverState<String>()
        _ = state.dockNotified("TextEdit", pointerInside: true)
        state.menuOpened()
        // The Dock clears its selection as the menu opens, then selects the
        // icon again under the pointer when the menu closes.
        #expect(state.dockNotified(nil, pointerInside: false) == nil)
        #expect(state.dockNotified("TextEdit", pointerInside: true) == nil)
        #expect(state.pointerReturned() == nil)
    }

    @Test("Leaving the menu icon ends the suppression, so a return previews it")
    func leavingMenuIconEndsSuppression() {
        var state = HoverState<String>()
        _ = state.dockNotified("TextEdit", pointerInside: true)
        state.menuOpened()
        _ = state.dockNotified(nil, pointerInside: false)
        _ = state.dockNotified("TextEdit", pointerInside: true)
        state.pointerLeftSuppressed()
        #expect(state.suppressed == nil)
        #expect(state.pointerReturned() == "TextEdit")
    }

    @Test("Leaving the Dock ends the suppression of the menu icon")
    func leavingDockEndsSuppression() {
        var state = HoverState<String>()
        _ = state.dockNotified("TextEdit", pointerInside: true)
        state.menuOpened()
        _ = state.dockNotified("TextEdit", pointerInside: false)
        #expect(state.dockNotified("TextEdit", pointerInside: true) == "TextEdit")
    }
}
