import XCTest

final class KeyboardEventsUtilsTests: XCTestCase {
    // alt-down > tab-down > tab-up > alt-up
    func testMostCommonSequence() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
    }

    // alt-down > tab-down > alt-up > tab-up
    func testSecondMostCommonSequence() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
    }

    // alt-down > tab-down > alt-up > tab-up
    func testSecondMostCommonSequenceVariation() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
    }

    // alt-down > alt-up > nextWindowShortcut-down
    // under heavy stress, macOS may miss sending us events
    // we poll NSEvent.modifierFlags to try to see if modifiers are up
    func testSequenceWithMissingEventAndWeCanSaveTheDay() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
    }

    // alt-down > alt-up > nextWindowShortcut-down
    // under heavy stress, macOS may miss sending us events
    // we poll NSEvent.modifierFlags to try to see if modifiers are up
    func testSequenceWithMissingEventAndWeCanNotSaveTheDay() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
    }

    // alt-down > alt-up > nextWindowShortcut-down > nextWindowShortcut-up
    func testOutOfOrderEvents() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        ModifierFlags.current = [.option]
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
    }

    //        handleKeyboardEvent(nil, nil, keycodeMap["h"], nil, false)
//        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["holdShortcut"])
    private func resetState() {
        App.app.appIsBeingUsed = false
        App.app.shortcutIndex = 0
        ControlsTab.shortcuts.values.forEach { $0.state = .up }
        ControlsTab.shortcutsActionsTriggered = []
    }
}

let keycodeMap: [Character: UInt32] = [
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
    "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
    "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
    "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
    "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
    "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
    "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C,
    "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
    "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25,
    "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D,
    "m": 0x2E, ".": 0x2F, "`": 0x32, " ": 0x31
]
