import XCTest
import Cocoa

/// Pins `NSWindow.isValidPersistedFrame`, the guard that stops a corrupt autosaved window frame from
/// aborting the app on restore (crash f481d5b0). The predicate mirrors AppKit's own rule: every edge
/// finite and within Int32 bounds. See `PersistedWindowFrameSpecs.md`.
final class PersistedWindowFrameTests: XCTestCase {

    // MARK: - A. Valid frames

    func testLiveEightTokenStringWithTrailingSpaceIsValid() {
        // The exact format AppKit writes to defaults: window x/y/w/h + screen x/y/w/h, trailing space.
        XCTAssertTrue(NSWindow.isValidPersistedFrame("834 503 380 450 0 0 2048 1121 "))
    }

    func testFourTokenWindowOnlyFrameIsValid() {
        XCTAssertTrue(NSWindow.isValidPersistedFrame("100 200 300 400"))
    }

    func testNegativeOriginIsValid() {
        // A secondary display placed left of / below the main one gives windows negative origins.
        XCTAssertTrue(NSWindow.isValidPersistedFrame("-1440 -900 1440 900"))
    }

    func testInt32MaxBoundaryIsValid() {
        XCTAssertTrue(NSWindow.isValidPersistedFrame("0 0 2147483647 0"))
    }

    // MARK: - B. Non-finite / out-of-range (the crash cases)

    func testNaNTokenIsInvalid() {
        XCTAssertFalse(NSWindow.isValidPersistedFrame("nan nan nan nan 0 0 2048 1121"))
    }

    func testInfiniteTokenIsInvalid() {
        XCTAssertFalse(NSWindow.isValidPersistedFrame("inf 0 100 100"))
    }

    func testValueBeyondInt32IsInvalid() {
        // 3e9 > Int32.max (2147483647): exactly the out-of-bounds value that fails CGRectContainsRect.
        XCTAssertFalse(NSWindow.isValidPersistedFrame("3000000000 0 100 100"))
    }

    func testFarEdgeOverflowIsInvalid() {
        // Origin is in range but x + w overflows Int32.max — AppKit rejects the resulting far edge.
        XCTAssertFalse(NSWindow.isValidPersistedFrame("2147483600 0 100 100"))
    }

    // MARK: - C. Malformed strings

    func testNegativeWidthOrHeightIsInvalid() {
        XCTAssertFalse(NSWindow.isValidPersistedFrame("0 0 -5 -5"))
    }

    func testFewerThanFourTokensIsInvalid() {
        XCTAssertFalse(NSWindow.isValidPersistedFrame("1 2 3"))
    }

    func testAllJunkTokensIsInvalid() {
        XCTAssertFalse(NSWindow.isValidPersistedFrame("a b c d"))
    }

    func testEmptyStringIsInvalid() {
        XCTAssertFalse(NSWindow.isValidPersistedFrame(""))
    }
}
