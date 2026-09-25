/// How far a running update download has come. Only the DMG download can be
/// measured; the checks after it (digest, signature, disk image copy, code
/// signature) report as one `verifying` phase.
public enum UpdateProgress: Sendable, Equatable {
    /// Bytes of the DMG received so far, and its size when the server sent one.
    case downloading(received: Int64, expected: Int64?)
    case verifying

    /// The share of the DMG received, from 0 to 1, or nil when it is unknown:
    /// no size from the server, or the checks after the download.
    public var fraction: Double? {
        guard case .downloading(let received, let expected?) = self, expected > 0 else { return nil }
        return min(max(Double(received) / Double(expected), 0), 1)
    }

    /// True when the step is worth a new report: another whole percent, or
    /// another whole MB when the size is unknown, or a change of phase.
    /// Keeps the window from redrawing per network packet.
    public static func isNewStep(from previous: Self?, to next: Self) -> Bool {
        guard case .downloading(let old, let oldSize)? = previous, case .downloading(let new, let newSize) = next,
            oldSize == newSize
        else { return previous != next }
        guard let size = newSize, size > 0 else { return old / 1_048_576 != new / 1_048_576 }
        return old * 100 / size != new * 100 / size
    }
}
