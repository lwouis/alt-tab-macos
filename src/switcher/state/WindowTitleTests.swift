import XCTest
import Cocoa

/// Pins `WindowTitle.singleLine`, the flattening `Window.bestEffortTitle` puts every title through so the
/// model never holds a line break (#6010). Group E measures a real `NSTextField` cell, which is the AppKit
/// behaviour the rest of the suite is reasoning about rather than a property of our own code.
///
/// Groups: A no-op · B break becomes a separator · C whitespace around the break · D breaks at the edges ·
/// E the measurement this exists for.
final class WindowTitleTests: XCTestCase {

    // MARK: - A. Nothing to do

    func testPlainTitleIsUntouched() {
        XCTAssertEqual(WindowTitle.singleLine("Monitor List | Datadog - Google Chrome"),
                       "Monitor List | Datadog - Google Chrome")
    }

    func testEmptyTitleStaysEmpty() {
        XCTAssertEqual(WindowTitle.singleLine(""), "")
    }

    func testTabsAndDoubleSpacesInsideALineAreKept() {
        XCTAssertEqual(WindowTitle.singleLine("a\tb  c"), "a\tb  c")
    }

    // MARK: - B. The break becomes a separator

    func testLineFeedBecomesOneSpace() {
        XCTAssertEqual(WindowTitle.singleLine("Channel\nFirst line of the post"),
                       "Channel First line of the post")
    }

    func testCarriageReturnBecomesOneSpace() {
        XCTAssertEqual(WindowTitle.singleLine("a\rb"), "a b")
    }

    func testCrlfBecomesOneSpaceNotTwo() {
        XCTAssertEqual(WindowTitle.singleLine("a\r\nb"), "a b")
    }

    func testBlankLineBetweenParagraphsBecomesOneSpace() {
        XCTAssertEqual(WindowTitle.singleLine("a\n\n\nb"), "a b")
    }

    func testVerticalTabAndFormFeedAreFlattened() {
        XCTAssertEqual(WindowTitle.singleLine("a\u{000B}b\u{000C}c"), "a b c")
    }

    func testNextLineAndUnicodeSeparatorsAreFlattened() {
        XCTAssertEqual(WindowTitle.singleLine("a\u{0085}b\u{2028}c\u{2029}d"), "a b c d")
    }

    // MARK: - C. Whitespace around the break

    func testIndentationAfterABreakIsDropped() {
        XCTAssertEqual(WindowTitle.singleLine("wants to run\n    import os\n    os.listdir()"),
                       "wants to run import os os.listdir()")
    }

    func testTrailingSpacesBeforeABreakAreDropped() {
        XCTAssertEqual(WindowTitle.singleLine("a  \n  b"), "a b")
    }

    // MARK: - D. Breaks at the edges

    func testLeadingBreakProducesNoSpace() {
        XCTAssertEqual(WindowTitle.singleLine("\nTitle"), "Title")
    }

    func testTrailingBreakProducesNoSpace() {
        XCTAssertEqual(WindowTitle.singleLine("Title\n"), "Title")
    }

    func testATitleOfNothingButBreaksIsEmpty() {
        XCTAssertEqual(WindowTitle.singleLine("\n\n"), "")
    }

    // MARK: - E. The measurement this exists for

    /// The whole reason the flattening exists: `NSCell.cellSize.height` grows by a line height per line
    /// break, and `TilesView` reads that number as "how tall is a title label".
    func testFlattenedTitleMeasuresOneLineHigh() {
        let multiLine = "Channel\nFirst line of the post\nSecond line"
        XCTAssertGreaterThan(measuredHeight(multiLine), measuredHeight("Channel") * 2)
        XCTAssertEqual(measuredHeight(WindowTitle.singleLine(multiLine)), measuredHeight("Channel"))
    }

    private func measuredHeight(_ title: String) -> CGFloat {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        return field.cell!.cellSize.height
    }
}
