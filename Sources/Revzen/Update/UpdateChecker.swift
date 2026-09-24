import Foundation
import RevzenCore

/// Reads the latest release from the GitHub API.
enum UpdateChecker {
    enum Failure: Error, LocalizedError {
        case noRelease
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noRelease: "No release of Revzen is published on GitHub yet."
            case .http(let status): "GitHub answered with HTTP \(status)."
            }
        }
    }

    static func latestRelease() async throws -> GitHubRelease {
        var request = request(AppInfo.releasesAPI, timeout: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        // GitHub answers 404 for `releases/latest` while no release exists.
        guard status(of: response) != 404 else { throw Failure.noRelease }
        try requireSuccess(response)
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func request(_ url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Revzen/\(AppInfo.versionString)", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func requireSuccess(_ response: URLResponse) throws {
        let status = status(of: response)
        guard (200..<300).contains(status) else { throw Failure.http(status) }
    }

    private static func status(of response: URLResponse) -> Int {
        (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
