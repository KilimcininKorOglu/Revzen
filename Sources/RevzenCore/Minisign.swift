import CryptoKit
import Foundation

/// Verifies minisign signatures (https://jedisct1.github.io/minisign/).
///
/// Formats, after base64 decoding:
/// - public key: algorithm "Ed" (2 bytes), key ID (8), Ed25519 key (32)
/// - signature line: algorithm (2), key ID (8), Ed25519 signature (64)
/// - global signature: Ed25519 signature (64) over the signature bytes
///   followed by the trusted comment text
///
/// Only the prehashed algorithm "ED" is accepted: the signature covers the
/// BLAKE2b-512 digest of the file. Legacy "Ed" signatures over the raw file
/// are rejected, as in the other apps of this developer.
public enum Minisign {
    public enum Failure: Error, Equatable {
        case malformedPublicKey
        case malformedSignature
        case keyMismatch
        case legacySignature
        case invalidSignature
        case invalidTrustedComment
    }

    public struct PublicKey: Sendable {
        let keyID: Data
        let key: Curve25519.Signing.PublicKey

        /// Takes the contents of a `.pub` file, or only its base64 line.
        public init(_ text: String) throws {
            guard let line = Self.keyLine(text),
                  let bytes = Data(base64Encoded: line), bytes.count == 42,
                  bytes.prefix(2) == Data("Ed".utf8),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: bytes.suffix(32)) else {
                throw Failure.malformedPublicKey
            }
            keyID = bytes.dropFirst(2).prefix(8)
            self.key = key
        }

        private static func keyLine(_ text: String) -> String? {
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("untrusted comment:") }
        }
    }

    /// Verifies `data` against the contents of a `.minisig` file and returns
    /// the trusted comment.
    @discardableResult
    public static func verify(_ data: Data, signature: String, publicKey: PublicKey) throws -> String {
        let parts = try SignatureFile(signature)
        guard parts.algorithm != Data("Ed".utf8) else { throw Failure.legacySignature }
        guard parts.algorithm == Data("ED".utf8) else { throw Failure.malformedSignature }
        guard parts.keyID == publicKey.keyID else { throw Failure.keyMismatch }
        guard publicKey.key.isValidSignature(parts.signature, for: BLAKE2b.hash(data)) else {
            throw Failure.invalidSignature
        }
        let signedComment = parts.signature + Data(parts.trustedComment.utf8)
        guard publicKey.key.isValidSignature(parts.globalSignature, for: signedComment) else {
            throw Failure.invalidTrustedComment
        }
        return parts.trustedComment
    }

    struct SignatureFile {
        static let trustedPrefix = "trusted comment: "

        let algorithm: Data
        let keyID: Data
        let signature: Data
        let trustedComment: String
        let globalSignature: Data

        init(_ text: String) throws {
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard lines.count >= 4,
                  let bytes = Data(base64Encoded: lines[1]), bytes.count == 74,
                  lines[2].hasPrefix(Self.trustedPrefix),
                  let global = Data(base64Encoded: lines[3]), global.count == 64 else {
                throw Failure.malformedSignature
            }
            algorithm = bytes.prefix(2)
            keyID = bytes.dropFirst(2).prefix(8)
            signature = bytes.suffix(64)
            trustedComment = String(lines[2].dropFirst(Self.trustedPrefix.count))
            globalSignature = global
        }
    }
}
