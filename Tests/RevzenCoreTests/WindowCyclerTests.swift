import Testing
@testable import RevzenCore

@Suite("WindowCycler")
struct WindowCyclerTests {
    @Test("Scrolling forward walks through every window and wraps to the first")
    func forwardWraps() {
        #expect(WindowCycler.next(count: 3, current: 0, step: 1) == 1)
        #expect(WindowCycler.next(count: 3, current: 2, step: 1) == 0)
    }

    @Test("Scrolling back from the first window wraps to the last")
    func backwardWraps() {
        #expect(WindowCycler.next(count: 3, current: 0, step: -1) == 2)
    }

    @Test("Without a focused window, forward starts at the first and backward at the last")
    func noCurrentWindow() {
        #expect(WindowCycler.next(count: 4, current: nil, step: 1) == 0)
        #expect(WindowCycler.next(count: 4, current: nil, step: -1) == 3)
    }

    @Test("An app without windows has nothing to cycle")
    func noWindows() {
        #expect(WindowCycler.next(count: 0, current: nil, step: 1) == nil)
    }
}

@Suite("ScrollStepper")
struct ScrollStepperTests {
    @Test("Each mouse wheel notch moves one window; down is next, up is previous")
    func wheelNotches() {
        var stepper = ScrollStepper()
        #expect(stepper.add(-1, continuous: false) == 1)
        #expect(stepper.add(1, continuous: false) == -1)
    }

    @Test("Small trackpad deltas add up to one step, not one step per event")
    func trackpadAccumulates() {
        var stepper = ScrollStepper()
        let steps = (0..<10).map { _ in stepper.add(-10, continuous: true) }
        #expect(steps.filter { $0 != 0 }.count == 2)
    }

    @Test("A fast flick moves one window per event, never more")
    func flickIsOneStep() {
        var stepper = ScrollStepper()
        #expect(stepper.add(-500, continuous: true) == 1)
    }

    @Test("Reversing the direction drops the partial amount of the old direction")
    func directionChangeResets() {
        var stepper = ScrollStepper()
        #expect(stepper.add(-30, continuous: true) == 0)
        #expect(stepper.add(30, continuous: true) == 0)
        #expect(stepper.add(15, continuous: true) == -1)
    }
}
