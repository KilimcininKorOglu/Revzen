import Foundation
import RevzenCore

extension UpdateService {
    /// The network, file and app actions the state machine drives. Tests
    /// replace them; the app uses `live`.
    struct Dependencies {
        var latestRelease: @MainActor () async throws -> GitHubRelease
        var currentVersion: @MainActor () -> SemanticVersion?
        var prepare: @MainActor (GitHubRelease, SemanticVersion, @escaping UpdateInstaller.ProgressReport) async throws -> URL
        var verifyStaged: @MainActor (URL, SemanticVersion) throws -> Void
        var install: @MainActor (URL) async throws -> Void
        /// Launch housekeeping: the relaunch report and the download cleanup.
        var cleanUp: @MainActor () -> Void

        static let live = Dependencies(
            latestRelease: { try await UpdateChecker.latestRelease() },
            currentVersion: { AppInfo.version },
            prepare: { try await UpdateInstaller.prepare($0, version: $1, report: $2) },
            verifyStaged: { try CodeCheck.verify(app: $0, version: $1) },
            install: { try await AppReplacer.installAndRelaunch($0) },
            cleanUp: {
                AppReplacer.reportLastRelaunch()
                Task.detached {
                    do {
                        try UpdateInstaller.removeStaleDownloads()
                    } catch {
                        DebugLog.error(.update, "could not clean the update downloads: \(error.localizedDescription)")
                    }
                }
            }
        )
    }
}
