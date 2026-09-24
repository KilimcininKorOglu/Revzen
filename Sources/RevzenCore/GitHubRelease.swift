import Foundation

/// The fields Revzen reads from the GitHub `releases/latest` endpoint.
public struct GitHubRelease: Decodable, Sendable, Equatable {
    public let tagName: String
    public let notes: String
    public let pageURL: URL
    public let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case notes = "body"
        case pageURL = "html_url"
        case assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        pageURL = try container.decode(URL.self, forKey: .pageURL)
        assets = try container.decode([ReleaseAsset].self, forKey: .assets)
    }

    public var version: SemanticVersion? {
        SemanticVersion(tagName)
    }

    /// The DMG and its minisign signature, or nil when either is missing.
    public func installAssets(dmgName: String) -> (dmg: ReleaseAsset, signature: ReleaseAsset)? {
        guard let dmg = assets.first(where: { $0.name == dmgName }),
              let signature = assets.first(where: { $0.name == dmgName + ".minisig" }) else { return nil }
        return (dmg, signature)
    }
}

/// One downloadable file of a GitHub release.
public struct ReleaseAsset: Decodable, Sendable, Equatable {
    public let name: String
    public let downloadURL: URL
    /// `sha256:<hex>`, computed by GitHub when the asset was uploaded.
    public let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case digest
    }

    public init(name: String, downloadURL: URL, digest: String?) {
        self.name = name
        self.downloadURL = downloadURL
        self.digest = digest
    }

    /// The lowercase hex SHA-256 from `digest`, or nil when GitHub did
    /// not report one or reported another algorithm.
    public var sha256: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }
}
