import Testing

@testable import RevzenCore

/// The pointer entered TextEdit.
private func hoveringTextEdit() -> HoverState<String> {
    var state = HoverState<String>()
    _ = state.dockNotified("TextEdit", pointerInside: true)
    return state
}

/// The pointer is on TextEdit, and its Dock menu just opened.
private func menuOpenedOnTextEdit() -> HoverState<String> {
    var state = hoveringTextEdit()
    state.menuOpened()
    return state
}

@Suite("HoverState")
struct HoverStateTests {
    @Test("Entering an icon previews it")
    func enterPreviews() {
        var state = HoverState<String>()
        #expect(state.dockNotified("TextEdit", pointerInside: true) == "TextEdit")
    }

    @Test("The notification sent when the pointer leaves the Dock does not preview the last icon")
    func leavingDockDoesNotPreview() {
        var state = hoveringTextEdit()
        #expect(state.dockNotified("TextEdit", pointerInside: false) == nil)
        state.pointerMovedAway()
        #expect(state.hovered == nil)
        #expect(state.pointerReturned() == nil)
    }

    @Test("Entering the Dock above the icon previews it once the pointer reaches the icon")
    func entryAboveIconWaitsForPointer() {
        var state = HoverState<String>()
        // The Dock selects the icon while the pointer is still above its frame.
        _ = state.dockNotified("TextEdit", pointerInside: false)
        #expect(state.hovered == "TextEdit")
        #expect(state.pointerReturned() == "TextEdit")
    }

    @Test("Returning to the same icon from the gap inside the Dock previews it again")
    func returnInsideDockPreviews() {
        #expect(hoveringTextEdit().pointerReturned() == "TextEdit")
    }
}

@Suite("HoverState and the Dock menu")
struct HoverStateMenuTests {
    @Test("After the Dock menu opens, the icon gets no preview until the pointer moves on")
    func menuSuppressesUntilAnotherIcon() {
        var state = menuOpenedOnTextEdit()
        #expect(state.pointerReturned() == nil)
        #expect(state.dockNotified("TextEdit", pointerInside: true) == nil)
        #expect(state.dockNotified("Finder", pointerInside: true) == "Finder")
        #expect(state.dockNotified("TextEdit", pointerInside: true) == "TextEdit")
    }

    @Test("The cleared selection of an opening menu keeps the icon suppressed when the menu closes")
    func menuSelectionClearKeepsSuppression() {
        var state = menuOpenedOnTextEdit()
        // The Dock clears its selection as the menu opens, then selects the
        // icon again under the pointer when the menu closes.
        _ = state.dockNotified(nil, pointerInside: false)
        #expect(state.dockNotified("TextEdit", pointerInside: true) == nil)
        #expect(state.suppressed == "TextEdit")
    }

    @Test("Leaving the menu icon ends the suppression, so a return previews it")
    func leavingMenuIconEndsSuppression() {
        var state = menuOpenedOnTextEdit()
        state.pointerLeftSuppressed()
        #expect(state.suppressed == nil)
        #expect(state.pointerReturned() == "TextEdit")
    }

    @Test("A notification with the pointer outside the menu icon keeps the suppression")
    func outsideNotificationKeepsSuppression() {
        var state = menuOpenedOnTextEdit()
        _ = state.dockNotified("TextEdit", pointerInside: false)
        #expect(state.pointerReturned() == nil)
    }
}
