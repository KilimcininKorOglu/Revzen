import CoreGraphics
import Testing
@testable import RevzenCore

@Suite("SpaceFilter")
struct SpaceFilterTests {
    private let document = CGRect(x: 0, y: 0, width: 800, height: 600)

    private func info(_ id: UInt32, pid: Int32 = 42, layer: Int = 0, bounds: CGRect? = nil, onScreen: Bool = false) -> WindowInfo {
        WindowInfo(id: id, ownerPID: pid, layer: layer, bounds: bounds ?? document, isOnScreen: onScreen)
    }

    @Test("An off-screen document window that AX did not report is a window on another Space")
    func offscreenUnknownWindowIsCandidate() {
        let list = [info(1), info(2)]
        #expect(SpaceFilter.otherSpaceCandidates(in: list, pid: 42, known: [2]) == [1])
    }

    @Test("Windows on the current screen are never candidates; AX already lists them")
    func onScreenWindowIsNotCandidate() {
        #expect(SpaceFilter.otherSpaceCandidates(in: [info(1, onScreen: true)], pid: 42, known: []).isEmpty)
    }

    @Test("Other apps, other layers and small helper windows are left out")
    func unrelatedWindowsAreLeftOut() {
        let list = [
            info(1, pid: 7),
            info(2, layer: 25),
            info(3, bounds: CGRect(x: 0, y: 0, width: 40, height: 20))
        ]
        #expect(SpaceFilter.otherSpaceCandidates(in: list, pid: 42, known: []).isEmpty)
    }
}
