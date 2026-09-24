/// The debug log file holds one event per line. Window titles and app names
/// of other apps reach the events, so control characters are escaped: a
/// title cannot start a forged line or send terminal escape sequences.
public enum LogLine {
    public static func singleLine(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            result += escaped(scalar) ?? String(scalar)
        }
        return result
    }

    private static func escaped(_ scalar: Unicode.Scalar) -> String? {
        switch scalar {
        case "\n": return "\\n"
        case "\r": return "\\r"
        case "\t": return "\\t"
        default:
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                return "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            default:
                return nil
            }
        }
    }
}
