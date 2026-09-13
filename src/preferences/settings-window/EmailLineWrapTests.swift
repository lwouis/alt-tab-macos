import XCTest
import Cocoa

/// Coverage for `EmailLineWrap`, the line breaker behind the sidebar upgrade pill's email.
///
/// Widths here are the real ones: the pill is the 175pt sidebar minus 2×10pt padding, and the text
/// keeps 6pt on each side, so 143pt of usable width at 13pt semibold.
final class EmailLineWrapTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private let width = CGFloat(143)
    private let maxLines = 3

    private func wrap(_ email: String, _ font: NSFont? = nil) -> EmailLineWrap.Result {
        EmailLineWrap.wrap(email, font: font ?? self.font, maxWidth: width, maxLines: maxLines)
    }

    private func fitted(_ email: String) -> NSFont {
        EmailLineWrap.fittedFont(email, baseFont: font, maxWidth: width, minSize: 11.5, maxLines: maxLines)
    }

    private func lineWidth(_ line: String, _ font: NSFont) -> CGFloat {
        (line as NSString).size(withAttributes: [.font: font]).width
    }

    func testShortEmailStaysOnOneLine() {
        let result = wrap("j.dupont@acme.fr")
        XCTAssertEqual(result.lines, ["j.dupont@acme.fr"])
        XCTAssertFalse(result.isTruncated)
    }

    func testBreaksAfterTheAtSign() {
        XCTAssertEqual(wrap("jean-francois.dubois@entreprise-solutions.fr").lines,
            ["jean-francois.dubois@", "entreprise-solutions.fr"],
            "the domain belongs on its own line: that's how people read an address")
    }

    func testBreaksAfterASeparatorWhenTheAtSignIsOutOfReach() {
        XCTAssertEqual(wrap("christopher.vandenberghe@universiteit-amsterdam.nl").lines,
            ["christopher.vandenber", "ghe@universiteit-", "amsterdam.nl"],
            "lines 2 and 3 break right after `-`, not mid-word")
    }

    func testKeepsEveryLineWithinTheAvailableWidth() {
        for email in ["j.dupont@acme.fr", "jean-francois.dubois@entreprise-solutions.fr",
                      "christopher.vandenberghe@universiteit-amsterdam.nl"] {
            for line in wrap(email).lines {
                XCTAssertLessThanOrEqual(lineWidth(line, font), width, "'\(line)' overflows the pill")
            }
        }
    }

    func testUntruncatedLinesRebuildTheAddress() {
        let email = "christopher.vandenberghe@universiteit-amsterdam.nl"
        let result = wrap(email)
        XCTAssertFalse(result.isTruncated)
        XCTAssertEqual(result.lines.joined(), email, "wrapping must not drop or add characters")
    }

    func testTruncatesTheTailPastTheLineBudget() {
        let email = "maximilian.von-hohenzollern@forschungsinstitut-bioinformatik.uni-heidelberg.de"
        let result = wrap(email)
        XCTAssertTrue(result.isTruncated)
        XCTAssertEqual(result.lines.count, maxLines)
        XCTAssertTrue(result.lines.last!.hasSuffix("…"))
        XCTAssertTrue(email.hasPrefix(result.lines.joined().dropLast()), "what is shown is a prefix of the address")
    }

    func testBreaksAnywhereWhenThereIsNoSeparatorToBreakOn() {
        let result = wrap("verylongsinglewordwithoutanyseparatorsatallxyz@x.io")
        XCTAssertEqual(result.lines.count, 3)
        XCTAssertFalse(result.isTruncated)
        XCTAssertEqual(result.lines[0], "verylongsinglewordwi", "no separator in reach, so it fills the line")
    }

    func testMakesProgressWhenNotEvenOneCharacterFits() {
        let result = EmailLineWrap.wrap("john@example.com", font: font, maxWidth: 2, maxLines: maxLines)
        XCTAssertEqual(result.lines.count, maxLines, "a width this small must still terminate, one character per line")
        XCTAssertTrue(result.isTruncated)
    }

    func testEmptyEmailProducesNoLines() {
        let result = wrap("")
        XCTAssertTrue(result.lines.isEmpty)
        XCTAssertFalse(result.isTruncated)
    }

    func testShrinksTheFontOnlyWhenThatSavesALine() {
        let nudged = fitted("john@cool-software.com")
        XCTAssertLessThan(nudged.pointSize, font.pointSize, "at 13pt this one spills a lonely 'com' onto a second line")
        XCTAssertEqual(wrap("john@cool-software.com", nudged).lines.count, 1)
    }

    func testKeepsTheBaseFontWhenShrinkingWouldNotSaveALine() {
        XCTAssertEqual(fitted("j.dupont@acme.fr").pointSize, font.pointSize, "already one line")
        XCTAssertEqual(fitted("maximilian.von-hohenzollern@forschungsinstitut-bioinformatik.uni-heidelberg.de").pointSize,
            font.pointSize, "still overflows 3 lines at every size, so shrinking buys nothing")
    }
}
