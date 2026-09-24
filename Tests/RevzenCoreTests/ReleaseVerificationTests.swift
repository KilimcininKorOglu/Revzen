import Foundation
import Testing

@testable import RevzenCore

@Suite("ReleaseVerification")
struct ReleaseVerificationTests {
    private let version = SemanticVersion(major: 1, minor: 2, patch: 3)
    private let bundleID = "com.kilimcininkoroglu.revzen"

    /// SHA-256 of the ASCII text "abc" (FIPS 180-2 test vector).
    private let abcDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test("A download passes only with the digest GitHub reported")
    func digest() {
        #expect(ReleaseVerification.digestMatches(Data("abc".utf8), sha256Hex: abcDigest))
        #expect(ReleaseVerification.digestMatches(Data("abc".utf8), sha256Hex: abcDigest.uppercased()))
        #expect(!ReleaseVerification.digestMatches(Data("abd".utf8), sha256Hex: abcDigest))
        #expect(!ReleaseVerification.digestMatches(Data("abc".utf8), sha256Hex: ""))
    }

    @Test("The trusted comment names this release, so an older signed DMG cannot pass as a newer one")
    func trustedComment() {
        #expect(ReleaseVerification.trustedComment(appName: "Revzen", version: version) == "Revzen 1.2.3")
        let older = ReleaseVerification.trustedComment(appName: "Revzen", version: SemanticVersion(major: 1, minor: 2, patch: 2))
        #expect(older != ReleaseVerification.trustedComment(appName: "Revzen", version: version))
    }

    struct BundleCase: Sendable, CustomTestStringConvertible {
        let bundleID: String?
        let shortVersion: String?
        let problem: String?
        var testDescription: String { "\(bundleID ?? "no bundle ID") \(shortVersion ?? "no version")" }
    }

    static let bundleCases = [
        BundleCase(bundleID: "com.kilimcininkoroglu.revzen", shortVersion: "1.2.3", problem: nil),
        BundleCase(
            bundleID: "com.example.other", shortVersion: "1.2.3", problem: "bundle ID is not com.kilimcininkoroglu.revzen"),
        BundleCase(bundleID: nil, shortVersion: "1.2.3", problem: "bundle ID is not com.kilimcininkoroglu.revzen"),
        BundleCase(bundleID: "com.kilimcininkoroglu.revzen", shortVersion: "1.2.2", problem: "version 1.2.2 is not 1.2.3"),
        BundleCase(bundleID: "com.kilimcininkoroglu.revzen", shortVersion: nil, problem: "version none is not 1.2.3")
    ]

    @Test("Only the expected app at the expected version is installed", arguments: bundleCases)
    func bundle(_ bundleCase: BundleCase) {
        let problem = ReleaseVerification.bundleProblem(
            bundleID: bundleCase.bundleID,
            shortVersion: bundleCase.shortVersion,
            expectedBundleID: bundleID,
            expectedVersion: version
        )
        #expect(problem == bundleCase.problem)
    }

    @Test("The mount point comes from the hdiutil attach plist")
    func mountPoint() throws {
        let plist: [String: Any] = [
            "system-entities": [
                ["content-hint": "GUID_partition_scheme", "dev-entry": "/dev/disk9"],
                ["content-hint": "Apple_HFS", "dev-entry": "/dev/disk9s1", "mount-point": "/Volumes/Revzen"]
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        #expect(try ReleaseVerification.mountPoint(inHdiutilPlist: data) == "/Volumes/Revzen")

        let unmounted = try PropertyListSerialization.data(
            fromPropertyList: ["system-entities": [["dev-entry": "/dev/disk9"]]], format: .xml, options: 0)
        #expect(try ReleaseVerification.mountPoint(inHdiutilPlist: unmounted) == nil)
        #expect(throws: (any Error).self) { try ReleaseVerification.mountPoint(inHdiutilPlist: Data("not a plist".utf8)) }
    }

    @Test("The code requirement asks for the developer's team and a notarization ticket")
    func codeRequirement() {
        #expect(
            ReleaseVerification.codeRequirement(teamID: "5U4P8ULV68")
                == "anchor apple generic and certificate leaf[subject.OU] = \"5U4P8ULV68\" and notarized")
    }

    @Test(
        "Only a release newer than the running version is offered",
        arguments: [
            ("1.2.4", "1.2.3", true), ("2.0.0", "1.9.9", true), ("1.2.3", "1.2.3", false),
            ("1.2.2", "1.2.3", false), ("bad", "1.2.3", false), ("1.2.4", "bad", false)
        ])
    func newer(latest: String, current: String, expected: Bool) {
        #expect(ReleaseVerification.isNewer(SemanticVersion(latest), than: SemanticVersion(current)) == expected)
    }

    @Test(
        "Only https release asset downloads of this repository are requested",
        arguments: [
            ("https://github.com/KilimcininKorOglu/Revzen/releases/download/v1.2.3/Revzen.dmg", true),
            ("http://github.com/KilimcininKorOglu/Revzen/releases/download/v1.2.3/Revzen.dmg", false),
            ("https://github.com/someone/Revzen/releases/download/v1.2.3/Revzen.dmg", false),
            ("https://192.168.1.1/KilimcininKorOglu/Revzen/releases/download/v1.2.3/Revzen.dmg", false),
            ("https://github.com.example.com/KilimcininKorOglu/Revzen/releases/download/v1.2.3/Revzen.dmg", false),
            ("https://user@github.com/KilimcininKorOglu/Revzen/releases/download/v1.2.3/Revzen.dmg", false),
            ("file:///KilimcininKorOglu/Revzen/releases/download/v1.2.3/Revzen.dmg", false)
        ])
    func assetURL(url: String, expected: Bool) throws {
        let parsed = try #require(URL(string: url))
        #expect(ReleaseVerification.isReleaseAssetURL(parsed, repository: "KilimcininKorOglu/Revzen") == expected)
    }

    @Test(
        "A download follows redirects only to GitHub asset hosts over https",
        arguments: [
            ("https://release-assets.githubusercontent.com/github-production-release-asset/1/2", true),
            ("https://objects.githubusercontent.com/x", true),
            ("https://github.com/x", true),
            ("http://release-assets.githubusercontent.com/x", false),
            ("https://evilgithubusercontent.com/x", false),
            ("https://localhost/x", false)
        ])
    func redirect(url: String, expected: Bool) throws {
        let parsed = try #require(URL(string: url))
        #expect(ReleaseVerification.isAssetRedirect(parsed) == expected)
    }
}
