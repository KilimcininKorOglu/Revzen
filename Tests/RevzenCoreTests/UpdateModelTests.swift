import Foundation
import Testing

@testable import RevzenCore

@Suite("SemanticVersion")
struct SemanticVersionTests {
    @Test("Release tags parse with or without the v prefix")
    func parsesTags() {
        #expect(SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion("10.0.12") == SemanticVersion(major: 10, minor: 0, patch: 12))
    }

    @Test(
        "Anything that is not three plain numbers is rejected",
        arguments: [
            "", "1.2", "1.2.3.4", "v1.2.x", "1.2.3-beta", "1..3", "-1.0.0", "+1.0.0", "v"
        ])
    func rejectsOtherShapes(text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test("Versions compare number by number, not as text, so 1.10.0 is newer than 1.9.9")
    func numericOrder() throws {
        let older = try #require(SemanticVersion("1.9.9"))
        let newer = try #require(SemanticVersion("1.10.0"))
        #expect(older < newer)
        #expect(!(newer < older))
    }
}

@Suite("GitHubRelease")
struct GitHubReleaseTests {
    private let json = """
        {
          "tag_name": "v1.1.0",
          "body": "Fixes",
          "html_url": "https://github.com/KilimcininKorOglu/Revzen/releases/tag/v1.1.0",
          "assets": [
            {"name": "Revzen.dmg", "browser_download_url": "https://example.com/Revzen.dmg",
             "digest": "sha256:ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789"},
            {"name": "Revzen.dmg.minisig", "browser_download_url": "https://example.com/Revzen.dmg.minisig",
             "digest": null}
          ]
        }
        """

    private func decode(_ text: String) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(text.utf8))
    }

    @Test("The latest release decodes with its version, notes and install assets")
    func decodesRelease() throws {
        let release = try decode(json)
        #expect(release.version == SemanticVersion("1.1.0"))
        #expect(release.notes == "Fixes")
        let assets = try #require(release.installAssets(dmgName: "Revzen.dmg"))
        #expect(assets.signature.name == "Revzen.dmg.minisig")
    }

    @Test("The GitHub digest yields a lowercase SHA-256 for the download check")
    func digestIsNormalized() throws {
        let dmg = try #require(try decode(json).installAssets(dmgName: "Revzen.dmg")?.dmg)
        #expect(dmg.sha256 == "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789")
    }

    @Test("A missing, foreign or malformed digest yields no SHA-256, so the installer refuses")
    func badDigests() {
        let url = URL(fileURLWithPath: "/tmp/x")
        for digest in [nil, "sha512:abcd", "sha256:xyz", "sha256:abcd"] {
            #expect(ReleaseAsset(name: "Revzen.dmg", downloadURL: url, digest: digest).sha256 == nil)
        }
    }

    @Test("A release without the signature asset cannot be installed")
    func missingSignature() throws {
        let unsigned = json.replacingOccurrences(of: "Revzen.dmg.minisig\"", with: "notes.txt\"")
        #expect(try decode(unsigned).installAssets(dmgName: "Revzen.dmg") == nil)
    }
}

@Suite("UpdateSchedule")
struct UpdateScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("The first launch checks at once")
    func firstLaunch() {
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
    }

    @Test("A check runs again only after 24 hours")
    func dailyInterval() {
        #expect(!UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
    }

    @Test("A clock set back before the last check does not block checks for days")
    func clockMovedBack() {
        #expect(UpdateSchedule.isDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}

@Suite("GitHubRateLimit")
struct GitHubRateLimitTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func reset(_ status: Int, _ headers: [String: String]) -> Date? {
        GitHubRateLimit.resetDate(status: status, header: { headers[$0] }, now: now)
    }

    @Test("A used-up limit reports the reset time GitHub sent")
    func primaryLimit() {
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1000600"]
        #expect(reset(403, headers) == Date(timeIntervalSince1970: 1_000_600))
        #expect(reset(429, headers) == Date(timeIntervalSince1970: 1_000_600))
    }

    @Test("A secondary limit reports now plus the retry-after seconds")
    func retryAfter() {
        #expect(reset(429, ["retry-after": "60"]) == now.addingTimeInterval(60))
    }

    @Test("A 403 with requests left, another status or no headers is not a rate limit")
    func notRateLimited() {
        #expect(reset(403, ["x-ratelimit-remaining": "12", "x-ratelimit-reset": "1000600"]) == nil)
        #expect(reset(403, [:]) == nil)
        #expect(reset(500, ["retry-after": "60"]) == nil)
    }
}
