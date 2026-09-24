import Foundation
import Testing
@testable import RevzenCore

@Suite("BLAKE2b")
struct BLAKE2bTests {
    /// Reference digests from Python's hashlib.blake2b. "abc" is also the
    /// RFC 7693 example. The inputs cover an empty message, a partial block,
    /// exactly one block, and several blocks with a partial last one.
    enum Vector: CaseIterable {
        case empty, abc, oneBlock, manyBlocks

        var input: Data {
            switch self {
            case .empty: Data()
            case .abc: Data("abc".utf8)
            case .oneBlock: Data(0..<128)
            case .manyBlocks: Data((0..<1000).map { UInt8($0 % 251) })
            }
        }

        var digest: String {
            switch self {
            case .empty:
                "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419"
                    + "d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce"
            case .abc:
                "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
                    + "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
            case .oneBlock:
                "2319e3789c47e2daa5fe807f61bec2a1a6537fa03f19ff32e87eecbfd64b7e0e"
                    + "8ccff439ac333b040f19b0c4ddd11a61e24ac1fe0f10a039806c5dcc0da3d115"
            case .manyBlocks:
                "c11e1c0340bd7e5a1b275f1230c962fad215ecb1391486e74e31b960a2f29963"
                    + "81a5fad092da06841d5f26e38f6ecfeaf441acbcd1c2de61aef121e7927175f5"
            }
        }
    }

    @Test("Digests match the reference implementation, across block boundaries", arguments: Vector.allCases)
    func referenceDigests(vector: Vector) {
        #expect(BLAKE2b.hash(vector.input).map { String(format: "%02x", $0) }.joined() == vector.digest)
    }
}

@Suite("Minisign")
struct MinisignTests {
    // A throwaway key made for these tests with `minisign -G -W`; its secret
    // key was never stored. The files were signed with minisign 0.12.
    private let publicKeyFile = """
    untrusted comment: minisign public key F156732A0B6E5138
    RWQ4UW4LKnNW8d4vJWQ1sd55J/ygvBwLU8YDWpmfMh0ZFvtr8FFdnMY7
    """
    private let data = Data("Revzen minisign fixture\n".utf8)
    private let signature = """
    untrusted comment: signature from minisign secret key
    RUQ4UW4LKnNW8ayiH3B2XVPX8ksd4irG/PjyIIa5Yk3+MKCjBB24DtLi+tNsONEVsTSomqPt9ebqlofX+At/Y32dTEtxcppJHAg=
    trusted comment: Revzen test fixture
    ze/DDL/IUPAicaC8qk+LWz2OuYDx4GEQJWlHk1bhks/I0eOUOzDhPKqqLW8e0jIUZn2+3rEewGUwZAKrRBzxDQ==
    """
    private let legacySignature = """
    untrusted comment: signature from minisign secret key
    RWQ4UW4LKnNW8YsD1v5P2I5Un8aKqlfMJDfqQ4SpBDPCkyax9FJR9NPKmZ4yTSXXQ721UD59IpeAGM+9cRJRCZRYq7WyzjlVbgQ=
    trusted comment: legacy
    Vj+BfbWcMOZhiuVCzszgnA1TvTctTbg4DtoBcIvIl/jCOnEB8i/gXQRaNPFKMzvIMIU7dKOrPvyhkB7L7TAwCw==
    """
    private let otherPublicKey = "RWRiucW5O4PzKSpAXm2eciOXkDGBhorstbQnT+HNb49tlRfxXymBvzA+"

    @Test("A file signed by the release key verifies and yields its trusted comment")
    func validSignature() throws {
        let key = try Minisign.PublicKey(publicKeyFile)
        #expect(try Minisign.verify(data, signature: signature, publicKey: key) == "Revzen test fixture")
    }

    @Test("A changed download is rejected")
    func tamperedData() throws {
        let key = try Minisign.PublicKey(publicKeyFile)
        #expect(throws: Minisign.Failure.invalidSignature) {
            try Minisign.verify(Data("Revzen minisign fixturE\n".utf8), signature: signature, publicKey: key)
        }
    }

    @Test("A changed trusted comment is rejected")
    func tamperedComment() throws {
        let key = try Minisign.PublicKey(publicKeyFile)
        let edited = signature.replacingOccurrences(of: "Revzen test fixture", with: "Revzen 9.9.9")
        #expect(throws: Minisign.Failure.invalidTrustedComment) {
            try Minisign.verify(data, signature: edited, publicKey: key)
        }
    }

    @Test("A signature from another key is rejected before any math")
    func otherKey() throws {
        let key = try Minisign.PublicKey(otherPublicKey)
        #expect(throws: Minisign.Failure.keyMismatch) {
            try Minisign.verify(data, signature: signature, publicKey: key)
        }
    }

    @Test("A legacy signature over the raw file is rejected")
    func legacyRejected() throws {
        let key = try Minisign.PublicKey(publicKeyFile)
        #expect(throws: Minisign.Failure.legacySignature) {
            try Minisign.verify(data, signature: legacySignature, publicKey: key)
        }
    }

    @Test("Truncated or garbage input is reported as malformed", arguments: ["", "only one line", "a\nb\nc\nd"])
    func malformedSignature(text: String) throws {
        let key = try Minisign.PublicKey(publicKeyFile)
        #expect(throws: Minisign.Failure.malformedSignature) {
            try Minisign.verify(data, signature: text, publicKey: key)
        }
    }

    @Test("A malformed public key is reported")
    func malformedKey() {
        #expect(throws: Minisign.Failure.malformedPublicKey) { try Minisign.PublicKey("not a key") }
    }
}
