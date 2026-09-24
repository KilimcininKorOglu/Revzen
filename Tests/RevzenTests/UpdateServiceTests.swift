import Foundation
import RevzenCore
import Testing

@testable import Revzen

/// Holds a fake step until the test lets it finish, so a test can act while
/// the step is still running.
@MainActor
private final class Gate<Value: Sendable> {
    private var waiting: [CheckedContinuation<Value, any Error>] = []
    private(set) var calls = 0

    func wait() async throws -> Value {
        calls += 1
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }

    var isWaiting: Bool { !waiting.isEmpty }

    func finish(_ result: sending Result<Value, any Error>) {
        let next = waiting.removeFirst()
        next.resume(with: result)
    }
}

@MainActor
private final class ErrorBox {
    var error: (any Error)?
}

private struct StepFailure: Error, LocalizedError {
    var errorDescription: String? { "step failed" }
}

/// An update service with fake network, file and app actions.
@MainActor
private final class Harness {
    let release = Gate<GitHubRelease>()
    let prepare = Gate<URL>()
    let install = Gate<Void>()
    let verifyError = ErrorBox()
    private(set) var presented = 0
    private let temporary = TemporaryDefaults()
    let service: UpdateService

    static let staged = URL(fileURLWithPath: "/tmp/Revzen.app")
    static let current = SemanticVersion(major: 1, minor: 0, patch: 0)
    static let newer = SemanticVersion(major: 1, minor: 1, patch: 0)

    init() {
        let dependencies = UpdateService.Dependencies(
            latestRelease: { [release] in try await release.wait() },
            currentVersion: { Self.current },
            prepare: { [prepare] _, _ in try await prepare.wait() },
            verifyStaged: { [verifyError] _, _ in if let error = verifyError.error { throw error } },
            install: { [install] _ in try await install.wait() },
            cleanUp: {}
        )
        service = UpdateService(defaults: temporary.defaults, dependencies: dependencies)
        service.onPresent = { [unowned self] in presented += 1 }
    }

    func finish() {
        service.stop()
        temporary.remove()
    }

    /// Lets the service tasks run until `condition` holds.
    func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
        #expect(condition(), "the condition did not hold", sourceLocation: sourceLocation)
    }

    static func release(_ tag: String) throws -> GitHubRelease {
        let json = """
            {"tag_name": "\(tag)", "body": "", "html_url": "https://github.com/KilimcininKorOglu/Revzen/releases/tag/\(tag)",
             "assets": []}
            """
        return try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    /// Waits until the service asks `gate`, then answers.
    func answer<Value>(_ gate: Gate<Value>, _ result: sending Result<Value, any Error>) async {
        await until { gate.isWaiting }
        gate.finish(result)
    }

    /// Runs a manual check that finds `newer` and waits for `.available`.
    func reachAvailable() async throws {
        service.checkNow()
        await answer(release, .success(try Self.release("v\(Self.newer)")))
        await until { if case .available = service.state { true } else { false } }
    }

    func reachReady() async throws {
        try await reachAvailable()
        service.download()
        await answer(prepare, .success(Self.staged))
        await until { service.state == .ready(Self.staged, Self.newer) }
    }
}

@MainActor
@Suite("UpdateService")
struct UpdateServiceTests {
    @Test("A scheduled check that finds a newer release shows the window")
    func scheduledFindsRelease() async throws {
        let harness = Harness()
        defer { harness.finish() }
        harness.service.start { true }
        await harness.answer(harness.release, .success(try Harness.release("v1.1.0")))
        await harness.until { if case .available = harness.service.state { true } else { false } }
        #expect(harness.presented == 1)
    }

    @Test("Up to date: a manual check says so, a scheduled check stays silent")
    func upToDate() async throws {
        let manual = Harness()
        defer { manual.finish() }
        manual.service.checkNow()
        await manual.answer(manual.release, .success(try Harness.release("v1.0.0")))
        await manual.until { manual.service.state == .upToDate }

        let scheduled = Harness()
        defer { scheduled.finish() }
        scheduled.service.start { true }
        await scheduled.answer(scheduled.release, .success(try Harness.release("v1.0.0")))
        await scheduled.until { scheduled.service.state == .idle }
        #expect(scheduled.presented == 0)
    }

    @Test("A failed check shows its error only to a manual check")
    func failedCheck() async throws {
        let harness = Harness()
        defer { harness.finish() }
        harness.service.checkNow()
        await harness.answer(harness.release, .failure(StepFailure()))
        await harness.until { harness.service.state == .failed("step failed") }
    }

    @Test("A manual check during a scheduled check gets the result of that check")
    func manualJoinsScheduled() async throws {
        let harness = Harness()
        defer { harness.finish() }
        harness.service.start { true }
        await harness.until { harness.release.isWaiting }
        harness.service.checkNow()
        await harness.until { harness.presented == 1 }
        harness.release.finish(.failure(StepFailure()))
        await harness.until { harness.service.state == .failed("step failed") }
        #expect(harness.release.calls == 1)
    }

    @Test("A download that fails after the window closed brings the window back")
    func failedDownloadShows() async throws {
        let harness = Harness()
        defer { harness.finish() }
        try await harness.reachAvailable()
        harness.service.download()
        harness.service.windowClosed()
        let shown = harness.presented
        await harness.answer(harness.prepare, .failure(StepFailure()))
        await harness.until { harness.service.state == .failed("step failed") }
        #expect(harness.presented == shown + 1)
    }

    @Test("Closing the window on an offered release ends it, so later checks run")
    func closedOfferEnds() async throws {
        let harness = Harness()
        defer { harness.finish() }
        try await harness.reachAvailable()
        harness.service.windowClosed()
        #expect(harness.service.state == .idle)
        harness.service.checkNow()
        await harness.until { harness.release.calls == 2 }
    }

    @Test("A second install request during an install starts no second install")
    func oneInstallAtATime() async throws {
        let harness = Harness()
        defer { harness.finish() }
        try await harness.reachReady()
        harness.service.installAndRelaunch()
        #expect(harness.service.state == .installing(Harness.newer))
        await harness.until { harness.install.isWaiting }
        harness.service.installAndRelaunch()
        for _ in 0..<100 { await Task.yield() }
        #expect(harness.install.calls == 1)
        harness.install.finish(.success(()))
    }

    @Test("A cancelled password prompt keeps the update ready to install")
    func cancelKeepsReady() async throws {
        let harness = Harness()
        defer { harness.finish() }
        try await harness.reachReady()
        harness.service.installAndRelaunch()
        await harness.answer(harness.install, .failure(AppReplacer.Failure.cancelled))
        await harness.until { harness.service.state == .ready(Harness.staged, Harness.newer) }
    }

    @Test("A staged app that fails the second check is not installed")
    func failedRecheckStopsInstall() async throws {
        let harness = Harness()
        defer { harness.finish() }
        try await harness.reachReady()
        harness.verifyError.error = StepFailure()
        harness.service.installAndRelaunch()
        await harness.until { harness.service.state == .failed("step failed") }
        #expect(harness.install.calls == 0)
    }
}
