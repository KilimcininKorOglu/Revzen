import Foundation
import Observation
import RevzenCore

/// Checks GitHub for a new release and drives the update window.
///
/// The background check runs at launch and then hourly, but asks GitHub only
/// when `UpdateSchedule` says a day has passed. Only a manual check reports
/// "up to date" and errors; a background check shows the window only when a
/// new release exists.
@MainActor
@Observable
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(GitHubRelease, SemanticVersion)
        case downloading(GitHubRelease, SemanticVersion)
        case ready(URL, SemanticVersion)
        case failed(String)
    }

    static let lastCheckKey = "updates.lastCheck"
    static let pollInterval: Duration = .seconds(60 * 60)

    private(set) var state = State.idle
    private(set) var lastCheck: Date?

    @ObservationIgnored var onPresent: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isAutoCheckEnabled: () -> Bool = { false }
    @ObservationIgnored private var poller: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    /// Starts the hourly poll. The setting is read on every poll, so a
    /// change in Settings applies without a restart.
    func start(isAutoCheckEnabled: @escaping () -> Bool) {
        self.isAutoCheckEnabled = isAutoCheckEnabled
        poller = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkIfDue()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        poller?.cancel()
        poller = nil
    }

    /// The "Check for Updates" command: ignores the daily schedule and
    /// always shows the result.
    func checkNow() {
        Task { await check(manual: true) }
    }

    func dismiss() {
        state = .idle
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .available, .ready: true
        case .idle, .upToDate, .failed: false
        }
    }
}

extension UpdateService {
    private func checkIfDue() {
        guard isAutoCheckEnabled(), UpdateSchedule.isDue(lastCheck: lastCheck, now: Date()) else { return }
        Task { await check(manual: false) }
    }

    private func check(manual: Bool) async {
        guard !isBusy else {
            if manual { onPresent?() }
            return
        }
        state = .checking
        if manual { onPresent?() }
        // Stored before the request, so a failing network does not turn the
        // hourly poll into an hourly request.
        let now = Date()
        lastCheck = now
        defaults.set(now, forKey: Self.lastCheckKey)
        do {
            apply(try await UpdateChecker.latestRelease(), manual: manual)
        } catch {
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = manual ? .failed(error.localizedDescription) : .idle
        }
    }

    private func apply(_ release: GitHubRelease, manual: Bool) {
        guard let latest = release.version, let current = AppInfo.version, latest > current else {
            state = manual ? .upToDate : .idle
            return
        }
        state = .available(release, latest)
        if !manual { onPresent?() }
    }
}

extension UpdateService {
    /// Downloads and verifies the release shown in the window.
    func download() {
        guard case .available(let release, let version) = state else { return }
        state = .downloading(release, version)
        Task {
            do {
                let app = try await UpdateInstaller.prepare(release, version: version)
                state = .ready(app, version)
            } catch {
                log.error("Update download failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    func installAndRelaunch() {
        guard case .ready(let app, _) = state else { return }
        Task {
            do {
                try await AppReplacer.installAndRelaunch(app)
            } catch {
                log.error("Update install failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }
}
