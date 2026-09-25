import Testing

@testable import RevzenCore

@Suite("UpdateProgress")
struct UpdateProgressTests {
    @Test("The bar shows the share of the DMG received, clamped to 0...1")
    func fraction() {
        #expect(UpdateProgress.downloading(received: 4_200_000, expected: 9_800_000).fraction == 4_200_000.0 / 9_800_000.0)
        #expect(UpdateProgress.downloading(received: 12, expected: 10).fraction == 1)
        #expect(UpdateProgress.downloading(received: -1, expected: 10).fraction == 0)
    }

    @Test("Without a size from the server, and while verifying, the bar is indeterminate")
    func unknownFraction() {
        #expect(UpdateProgress.downloading(received: 500, expected: nil).fraction == nil)
        #expect(UpdateProgress.downloading(received: 500, expected: 0).fraction == nil)
        #expect(UpdateProgress.verifying.fraction == nil)
    }

    @Test("The window redraws once per whole percent, not per network packet")
    func throttling() {
        let step = { (received: Int64) in UpdateProgress.downloading(received: received, expected: 1000) }
        #expect(UpdateProgress.isNewStep(from: nil, to: step(0)))
        #expect(!UpdateProgress.isNewStep(from: step(100), to: step(105)))
        #expect(UpdateProgress.isNewStep(from: step(105), to: step(110)))
        #expect(UpdateProgress.isNewStep(from: step(990), to: step(1000)))
        #expect(UpdateProgress.isNewStep(from: step(1000), to: .verifying))
    }

    @Test("Without a known size, the window redraws once per whole MB")
    func unknownSizeSteps() {
        let step = { (received: Int64) in UpdateProgress.downloading(received: received, expected: nil) }
        #expect(!UpdateProgress.isNewStep(from: step(100), to: step(200_000)))
        #expect(UpdateProgress.isNewStep(from: step(1_000_000), to: step(1_100_000)))
    }
}
