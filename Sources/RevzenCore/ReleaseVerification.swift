import CryptoKit
import Foundation

/// The decisions that make a downloaded release trusted. The updater reads
/// files, mounts the image and checks the code signature; these functions
/// decide on the results.
public enum ReleaseVerification {
    /// True when the SHA-256 of `data` is the hex digest GitHub reported.
    public static func digestMatches(_ data: Data, sha256Hex: String) -> Bool {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return actual == sha256Hex.lowercased()
    }

    /// The release pipeline signs with this trusted comment, so an older
    /// signed DMG cannot pass as a newer release.
    public static func trustedComment(appName: String, version: SemanticVersion) -> String {
        "\(appName) \(version)"
    }

    /// Nil when the staged app is the expected app at the expected version,
    /// otherwise the reason it is not.
    public static func bundleProblem(
        bundleID: String?,
        shortVersion: String?,
        expectedBundleID: String,
        expectedVersion: SemanticVersion
    ) -> String? {
        guard bundleID == expectedBundleID else { return "bundle ID is not \(expectedBundleID)" }
        guard shortVersion.flatMap(SemanticVersion.init) == expectedVersion else {
            return "version \(shortVersion ?? "none") is not \(expectedVersion)"
        }
        return nil
    }

    /// The first mount point in the `-plist` output of `hdiutil attach`.
    public static func mountPoint(inHdiutilPlist plist: Data) throws -> String? {
        let root = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let entities = root?["system-entities"] as? [[String: Any]] ?? []
        return entities.lazy.compactMap { $0["mount-point"] as? String }.first
    }

    /// A notarized app signed with a Developer ID certificate of `teamID`.
    public static func codeRequirement(teamID: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\" and notarized"
    }

    /// True for an https download of a release asset of `repository`
    /// (`owner/name`) on github.com. The URL comes from the GitHub API
    /// response, so it is checked before any request.
    public static func isReleaseAssetURL(_ url: URL, repository: String) -> Bool {
        url.scheme == "https" && url.host() == "github.com" && url.user() == nil
            && url.path().hasPrefix("/\(repository)/releases/download/")
    }

    /// True for a redirect target that GitHub uses for release assets.
    public static func isAssetRedirect(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user() == nil, let host = url.host() else { return false }
        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    /// True only when both versions are known and `latest` is newer.
    public static func isNewer(_ latest: SemanticVersion?, than current: SemanticVersion?) -> Bool {
        guard let latest, let current else { return false }
        return latest > current
    }
}
