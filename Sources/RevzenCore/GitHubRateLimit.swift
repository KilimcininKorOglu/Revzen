import Foundation

/// Reads the GitHub REST API rate-limit answer. GitHub answers 403 or 429
/// when the limit for unauthenticated requests from one address is used up.
public enum GitHubRateLimit {
    /// The time after which a new request can succeed, or nil when the
    /// response is not a rate-limit answer. `header` looks up a response
    /// header by name.
    public static func resetDate(status: Int, header: (String) -> String?, now: Date) -> Date? {
        guard status == 403 || status == 429 else { return nil }
        if let seconds = header("retry-after").flatMap(TimeInterval.init) {
            return now.addingTimeInterval(seconds)
        }
        guard header("x-ratelimit-remaining") == "0",
            let reset = header("x-ratelimit-reset").flatMap(TimeInterval.init)
        else { return nil }
        return Date(timeIntervalSince1970: reset)
    }
}
