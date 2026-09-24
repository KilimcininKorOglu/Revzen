import Foundation
import RevzenCore
import Security

/// Why an update was not installed.
enum UpdateFailure: Error, LocalizedError {
    case missingAssets
    case missingDigest
    case digestMismatch
    case signature(Minisign.Failure)
    case wrongTrustedComment(String)
    case mountPointMissing
    case codeSignature(OSStatus)
    case wrongApp(String)
    case untrustedURL(URL)

    var errorDescription: String? {
        switch self {
        case .missingAssets: "The release has no \(AppInfo.dmgName) with a minisign signature."
        case .missingDigest: "GitHub reported no SHA-256 digest for the download."
        case .digestMismatch: "The download does not match the SHA-256 digest that GitHub reported."
        case .signature(let failure): "The minisign signature is not valid (\(failure))."
        case .wrongTrustedComment(let comment): "The signature belongs to another release: \(comment)."
        case .mountPointMissing: "The disk image did not report a mount point."
        case .codeSignature(let status): "The new app is not notarized or not signed by the developer (OSStatus \(status))."
        case .wrongApp(let detail): "The disk image holds an unexpected app: \(detail)."
        case .untrustedURL(let url): "The release lists a download outside the GitHub releases of Revzen: \(url)."
        }
    }
}

/// Downloads a release, verifies it and stages the new app in the cache.
///
/// Checks, in order: the SHA-256 digest GitHub computed at upload, the
/// minisign signature of the release key, and the code signature with the
/// developer's Team ID and a notarization ticket.
enum UpdateInstaller {
    static let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "Revzen/updates", directoryHint: .isDirectory)
    static let cacheLifetime: TimeInterval = 7 * 24 * 60 * 60

    /// Returns the verified app inside the cache.
    static func prepare(_ release: GitHubRelease, version: SemanticVersion) async throws -> URL {
        guard let assets = release.installAssets(dmgName: AppInfo.dmgName) else { throw UpdateFailure.missingAssets }
        guard let digest = assets.dmg.sha256 else { throw UpdateFailure.missingDigest }
        for url in [assets.dmg.downloadURL, assets.signature.downloadURL]
        where !ReleaseVerification.isReleaseAssetURL(url, repository: AppInfo.repository) {
            throw UpdateFailure.untrustedURL(url)
        }
        try removeStaleDownloads()
        let folder = cacheRoot.appending(path: version.description, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dmg = try await download(assets.dmg.downloadURL, to: folder.appending(path: AppInfo.dmgName))
        let signature = try await download(assets.signature.downloadURL, to: folder.appending(path: assets.signature.name))
        let data = try Data(contentsOf: dmg)
        try verifyDigest(of: data, expected: digest)
        try verifySignature(of: data, signatureFile: signature, version: version)

        let app = try await DiskImage.copyApp(from: dmg, into: folder)
        try CodeCheck.verify(app: app, version: version)
        return app
    }

    private static func download(_ url: URL, to destination: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(
            for: UpdateChecker.request(url, timeout: 60), delegate: AssetRedirectGuard())
        try UpdateChecker.requireSuccess(response)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Deletes the folders of releases that are not newer than the running
    /// app, which holds the downloads of an installed update, and folders
    /// older than a week. Runs at launch and before each download.
    static func removeStaleDownloads() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: cacheRoot.path) else { return }
        let limit = Date().addingTimeInterval(-cacheLifetime)
        let folders = try manager.contentsOfDirectory(
            at: cacheRoot, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for folder in folders {
            let modified = try folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let installed = !ReleaseVerification.isNewer(SemanticVersion(folder.lastPathComponent), than: AppInfo.version)
            if installed || modified.map({ $0 < limit }) ?? false {
                DebugLog.event(.update, "removing the download folder \(folder.lastPathComponent)")
                try manager.removeItem(at: folder)
            }
        }
    }
}

extension UpdateInstaller {
    static func verifyDigest(of data: Data, expected: String) throws {
        guard ReleaseVerification.digestMatches(data, sha256Hex: expected) else { throw UpdateFailure.digestMismatch }
    }

    static func verifySignature(of data: Data, signatureFile: URL, version: SemanticVersion) throws {
        let text = try String(contentsOf: signatureFile, encoding: .utf8)
        let comment: String
        do {
            let key = try Minisign.PublicKey(AppInfo.minisignPublicKey)
            comment = try Minisign.verify(data, signature: text, publicKey: key)
        } catch let failure as Minisign.Failure {
            throw UpdateFailure.signature(failure)
        }
        guard comment == ReleaseVerification.trustedComment(appName: AppInfo.name, version: version) else {
            throw UpdateFailure.wrongTrustedComment(comment)
        }
    }
}

/// Follows a redirect only to the hosts GitHub serves release assets from.
/// A refused redirect ends the download with the redirect status.
private final class AssetRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, ReleaseVerification.isAssetRedirect(url) else {
            DebugLog.error(.update, "refused the download redirect to \(request.url?.absoluteString ?? "no URL")")
            return nil
        }
        return request
    }
}

/// Mounts a DMG, copies the app out and always detaches the image.
enum DiskImage {
    static func copyApp(from dmg: URL, into folder: URL) async throws -> URL {
        let plist = try await ProcessRunner.run(
            "/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-plist", dmg.path]
        )
        let mountPoint = try mountPoint(in: plist)
        do {
            let app = folder.appending(path: "\(AppInfo.name).app", directoryHint: .isDirectory)
            _ = try await ProcessRunner.run(
                "/usr/bin/ditto", [mountPoint.appending(path: "\(AppInfo.name).app").path, app.path]
            )
            try await detach(mountPoint)
            return app
        } catch {
            do {
                try await detach(mountPoint)
            } catch let detachError {
                // The copy error is the one the user needs; the detach
                // failure only leaves a mounted image behind.
                DebugLog.error(.update, "could not detach \(mountPoint.path): \(detachError.localizedDescription)")
            }
            throw error
        }
    }

    private static func detach(_ mountPoint: URL) async throws {
        _ = try await ProcessRunner.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    private static func mountPoint(in plist: Data) throws -> URL {
        guard let path = try ReleaseVerification.mountPoint(inHdiutilPlist: plist) else {
            throw UpdateFailure.mountPointMissing
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Checks the staged app before it replaces the running one.
enum CodeCheck {
    static let requirement = ReleaseVerification.codeRequirement(teamID: AppInfo.teamID)

    static func verify(app: URL, version: SemanticVersion) throws {
        let bundle = Bundle(url: app)
        let problem = ReleaseVerification.bundleProblem(
            bundleID: bundle?.bundleIdentifier,
            shortVersion: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            expectedBundleID: AppInfo.bundleID,
            expectedVersion: version
        )
        if let problem { throw UpdateFailure.wrongApp(problem) }
        try checkSignature(of: app)
    }

    private static func checkSignature(of app: URL) throws {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        guard status == errSecSuccess, let code else { throw UpdateFailure.codeSignature(status) }
        var compiled: SecRequirement?
        status = SecRequirementCreateWithString(requirement as CFString, [], &compiled)
        guard status == errSecSuccess, let compiled else { throw UpdateFailure.codeSignature(status) }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        status = SecStaticCodeCheckValidity(code, flags, compiled)
        guard status == errSecSuccess else { throw UpdateFailure.codeSignature(status) }
    }
}
