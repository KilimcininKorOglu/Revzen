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
    /// A manual check arrived while a scheduled check was running.
    @ObservationIgnored private var joinedManual = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    /// Starts the hourly poll. The setting is read on every poll, so a
    /// change in Settings applies without a restart.
    func start(isAutoCheckEnabled: @escaping () -> Bool) {
        self.isAutoCheckEnabled = isAutoCheckEnabled
        Task.detached {
            do {
                try UpdateInstaller.removeStaleDownloads()
            } catch {
                DebugLog.error(.update, "could not clean the update downloads: \(error.localizedDescription)")
            }
        }
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

    /// The window closed with its title bar button. A shown result ends as
    /// with "Later" or "OK". A running step continues and shows its result.
    func windowClosed() {
        switch state {
        case .available, .upToDate, .failed: state = .idle
        case .idle, .checking, .downloading, .ready: break
        }
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
            if manual { joinRunningStep() }
            return
        }
        state = .checking
        DebugLog.event(.update, "checking GitHub (\(manual ? "manual" : "scheduled"))")
        if manual { onPresent?() }
        // Stored before the request, so a failing network does not turn the
        // hourly poll into an hourly request.
        let now = Date()
        lastCheck = now
        defaults.set(now, forKey: Self.lastCheckKey)
        do {
            let release = try await UpdateChecker.latestRelease()
            apply(release, manual: takeManual(manual))
        } catch {
            DebugLog.error(.update, "update check failed: \(error.localizedDescription)")
            state = takeManual(manual) ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Shows the window of the running step. A manual check that joins a
    /// scheduled check gets the result of that check.
    private func joinRunningStep() {
        if state == .checking { joinedManual = true }
        onPresent?()
    }

    /// True when this check or a manual check that joined it shows the result.
    private func takeManual(_ manual: Bool) -> Bool {
        defer { joinedManual = false }
        return manual || joinedManual
    }

    private func apply(_ release: GitHubRelease, manual: Bool) {
        guard ReleaseVerification.isNewer(release.version, than: AppInfo.version), let latest = release.version else {
            DebugLog.event(.update, "latest release \(release.tagName), up to date")
            state = manual ? .upToDate : .idle
            return
        }
        DebugLog.event(.update, "\(latest) is available")
        state = .available(release, latest)
        if !manual { onPresent?() }
    }
}

extension UpdateService {
    /// Downloads and verifies the release shown in the window.
    func download() {
        guard case .available(let release, let version) = state else { return }
        state = .downloading(release, version)
        perform("download") { [self] in
            let app = try await UpdateInstaller.prepare(release, version: version)
            DebugLog.event(.update, "\(version) verified and staged at \(app.path)")
            state = .ready(app, version)
            onPresent?()
        }
    }

    func installAndRelaunch() {
        guard case .ready(let app, _) = state else { return }
        DebugLog.event(.update, "installing \(app.path) and relaunching")
        perform("install") {
            try await AppReplacer.installAndRelaunch(app)
        }
    }

    /// Runs one update step; a failure shows in the window, also when the
    /// user closed it during the step.
    private func perform(_ step: String, _ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                DebugLog.error(.update, "update \(step) failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
                onPresent?()
            }
        }
    }
}
