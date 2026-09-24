import Testing

@testable import RevzenCore

@Suite("LogLine")
struct LogLineTests {
    @Test("A window title with a newline cannot start a forged log line")
    func newlineIsEscaped() {
        let title = "Report\n2026-09-24T10:00:00.000+03:00 [update] ERROR forged"
        let line = LogLine.singleLine("[preview] show 'Report' \(title)")
        #expect(!line.contains("\n"))
        #expect(line.hasSuffix("Report\\n2026-09-24T10:00:00.000+03:00 [update] ERROR forged"))
    }

    @Test(
        "Control characters and Unicode line breaks are escaped",
        arguments: [
            ("a\rb", "a\\rb"), ("a\tb", "a\\tb"), ("\u{1B}[31mred", "\\u{1B}[31mred"),
            ("a\u{2028}b", "a\\u{2028}b"), ("a\u{85}b", "a\\u{85}b"), ("a\u{0}b", "a\\u{0}b")
        ])
    func controlCharactersAreEscaped(input: String, expected: String) {
        #expect(LogLine.singleLine(input) == expected)
    }

    @Test("Plain text, including non-ASCII names, stays as it is")
    func plainTextIsKept() {
        #expect(LogLine.singleLine("Kerem Gök's Dokümanlar · 日本語 'x' id=42") == "Kerem Gök's Dokümanlar · 日本語 'x' id=42")
    }
}
