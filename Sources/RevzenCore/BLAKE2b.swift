import Foundation

/// BLAKE2b-512 as specified in RFC 7693, unkeyed. minisign signs the
/// BLAKE2b-512 digest of a file, and CryptoKit has no BLAKE2b.
public enum BLAKE2b {
    public static let digestLength = 64
    static let blockLength = 128

    static let initialState: [UInt64] = [
        0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b, 0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
        0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f, 0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179
    ]

    static let sigma: [[Int]] = [
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
        [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
        [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
        [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
        [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
        [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
        [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
        [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
        [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
        [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
    ]

    public static func hash(_ data: Data) -> Data {
        var state = initialState
        // Parameter block: digest length 64, no key, fanout 1, depth 1.
        state[0] ^= 0x0101_0000 ^ UInt64(digestLength)
        let bytes = [UInt8](data)
        var offset = 0
        // Every full block except the last one is compressed as non-final.
        while bytes.count - offset > blockLength {
            compress(&state, block: bytes[offset..<offset + blockLength], counter: UInt64(offset + blockLength), last: false)
            offset += blockLength
        }
        var final = [UInt8](bytes[offset...])
        final += [UInt8](repeating: 0, count: blockLength - final.count)
        compress(&state, block: final[...], counter: UInt64(bytes.count), last: true)
        var digest = Data(capacity: digestLength)
        for word in state {
            withUnsafeBytes(of: word.littleEndian) { digest.append(contentsOf: $0) }
        }
        return digest
    }

    /// The low 64 bits of the byte counter suffice: a file of 2^64 bytes
    /// is not a Revzen release.
    static func compress(_ state: inout [UInt64], block: ArraySlice<UInt8>, counter: UInt64, last: Bool) {
        let message = words(block)
        var work = state + initialState
        work[12] ^= counter
        if last {
            work[14] = ~work[14]
        }
        for round in 0..<12 {
            let order = sigma[round % 10]
            mix(&work, [0, 4, 8, 12], message[order[0]], message[order[1]])
            mix(&work, [1, 5, 9, 13], message[order[2]], message[order[3]])
            mix(&work, [2, 6, 10, 14], message[order[4]], message[order[5]])
            mix(&work, [3, 7, 11, 15], message[order[6]], message[order[7]])
            mix(&work, [0, 5, 10, 15], message[order[8]], message[order[9]])
            mix(&work, [1, 6, 11, 12], message[order[10]], message[order[11]])
            mix(&work, [2, 7, 8, 13], message[order[12]], message[order[13]])
            mix(&work, [3, 4, 9, 14], message[order[14]], message[order[15]])
        }
        for index in 0..<8 {
            state[index] ^= work[index] ^ work[index + 8]
        }
    }

    /// The G function of RFC 7693 on four lanes of the work vector.
    static func mix(_ work: inout [UInt64], _ lanes: [Int], _ first: UInt64, _ second: UInt64) {
        let (lane0, lane1, lane2, lane3) = (lanes[0], lanes[1], lanes[2], lanes[3])
        work[lane0] = work[lane0] &+ work[lane1] &+ first
        work[lane3] = rotateRight(work[lane3] ^ work[lane0], 32)
        work[lane2] = work[lane2] &+ work[lane3]
        work[lane1] = rotateRight(work[lane1] ^ work[lane2], 24)
        work[lane0] = work[lane0] &+ work[lane1] &+ second
        work[lane3] = rotateRight(work[lane3] ^ work[lane0], 16)
        work[lane2] = work[lane2] &+ work[lane3]
        work[lane1] = rotateRight(work[lane1] ^ work[lane2], 63)
    }

    static func rotateRight(_ value: UInt64, _ count: UInt64) -> UInt64 {
        (value >> count) | (value << (64 - count))
    }

    static func words(_ block: ArraySlice<UInt8>) -> [UInt64] {
        let start = block.startIndex
        return (0..<16).map { index in
            (0..<8).reduce(UInt64(0)) { word, byte in
                word | UInt64(block[start + index * 8 + byte]) << (8 * UInt64(byte))
            }
        }
    }
}
