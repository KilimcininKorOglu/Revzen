import Foundation
import RevzenCore

/// Facts about this app that the updater and the About section use.
enum AppInfo {
    static let name = "Revzen"
    static let developer = "Kerem Gök"
    static let repository = "KilimcininKorOglu/Revzen"
    static let repositoryURL = URL(string: "https://github.com/KilimcininKorOglu/Revzen")!
    static let xURL = URL(string: "https://x.com/KogOglan")!
    static let releasesAPI = URL(string: "https://api.github.com/repos/KilimcininKorOglu/Revzen/releases/latest")!
    static let bundleID = "com.kilimcininkoroglu.revzen"
    static let teamID = "5U4P8ULV68"
    static let dmgName = "Revzen.dmg"

    /// The minisign public key of the release pipeline. Release DMGs are
    /// signed with the matching secret key in CI.
    static let minisignPublicKey = """
    untrusted comment: minisign public key 29F3833BB9C5B962
    RWRiucW5O4PzKSpAXm2eciOXkDGBhorstbQnT+HNb49tlRfxXymBvzA+
    """

    static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    /// Nil only for a build without a valid version in Info.plist.
    static var version: SemanticVersion? {
        SemanticVersion(versionString)
    }
}
