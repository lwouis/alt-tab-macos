import Cocoa
import ShortcutRecorder
import XCTest

final class ShortcutSymbolsTests: XCTestCase {
    func testModifierSymbolsKeepTheirFlags() throws {
        let symbols: [(String, NSEvent.ModifierFlags)] = [
            ("⌥", .option), ("⌘", .command), ("⇧", .shift), ("⌃", .control),
            ("⌃⌥⇧⌘", [.control, .option, .shift, .command]),
        ]
        for (symbol, flags) in symbols {
            let shortcut = try XCTUnwrap(Shortcut(keyEquivalent: symbol), symbol)
            XCTAssertEqual(shortcut.keyCode, .none, symbol)
            XCTAssertEqual(shortcut.modifierFlags, flags, symbol)
        }
    }

    func testSpecialKeySymbolsKeepTheirKeyCodes() throws {
        let symbols: [(String, KeyCode)] = [
            ("⇥", .tab), ("⎋", .escape), ("←", .leftArrow), ("→", .rightArrow),
            ("↑", .upArrow), ("↓", .downArrow), ("⌫", .delete),
        ]
        for (symbol, code) in symbols {
            let shortcut = try XCTUnwrap(Shortcut(keyEquivalent: symbol), symbol)
            XCTAssertEqual(shortcut.keyCode, code, symbol)
            XCTAssertEqual(shortcut.modifierFlags, [], symbol)
        }
    }
}
