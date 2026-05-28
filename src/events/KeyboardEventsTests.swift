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

    // alt-down > tab-down > tab-up > w-down > w-up > alt-up
    func testCloseWindowShortcut() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(nil, nil, keycodeMap["w"], [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "closeWindowShortcut"])
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "closeWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "closeWindowShortcut", "holdShortcut"])
    }

    func testOnReleaseDoNothing() throws {
        resetState()
        Preferences.shortcutStyle = .doNothingOnRelease
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
    }

    func testOnReleaseToggleSearchModeDoesNotFocus() throws {
        resetState()
        Preferences.shortcutStyle = .searchOnRelease
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
    }

    // alt-down > tab-down > tab-up > `-down > `-up
    func testTransitionFromOneShortcutToAnother() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        handleKeyboardEvent(nil, nil, keycodeMap["`"], [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "nextWindowShortcut2"])
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "nextWindowShortcut2"])
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "nextWindowShortcut2", "holdShortcut2"])
    }

    private func resetState() {
        SwitcherSession.current = nil
        Preferences.shortcutStyle = .focusOnRelease
        ControlsTab.shortcuts.values.forEach { $0.state = .up }
        ControlsTab.shortcutsActionsTriggered = []
    }

    // Issue #5585: Escape (kVK_Escape = 53) reaches the matcher via the cghid event tap in
    // KeyboardEvents on the real device. These tests exercise the matcher logic that the tap
    // routes into — not the OS event delivery itself.
    func testEscapeFiresCancelShortcutWhileSwitcherActiveWithOptionHeld() throws {
        resetState()
        // Set up: switcher is open, Option still held (the original bug repro).
        SwitcherSession.current = SwitcherSession()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, escapeKeycode, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["cancelShortcut"])
    }

    func testEscapeDoesNothingWhenSwitcherIsClosed() throws {
        resetState()
        SwitcherSession.current = nil
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, escapeKeycode, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, [])
    }

    // MARK: - Modifier flag filtering (NSEvent.ModifierFlags.cleaned)
    //
    // NSEvent.addLocalMonitorForEvents sometimes emits modifier flags with bits we don't care about
    // (function-key bit; raw bits like 0x120 that AppKit hands back unfiltered). `cleaned()` is the
    // intersection that strips those down to the supported set before the matcher sees them. Lives
    // in `ATShortcut.swift` next to the matcher that calls it; tested here because no
    // ATShortcutTests.swift exists yet and modifier handling is the keyboard-events neighborhood.

    func testCleanedKeepsValidModifierBits() {
        let valid: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .capsLock]
        XCTAssertEqual(valid.cleaned(), valid, "every supported bit should survive cleaning")
    }

    func testCleanedDropsFunctionAndUnknownBits() {
        let dirty: NSEvent.ModifierFlags = [.option, .function]
        XCTAssertEqual(dirty.cleaned(), [.option], "the function bit is not a modifier we support")
        let withGarbage = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x120)
        XCTAssertEqual(withGarbage.cleaned(), [.option], "stray AppKit bits (e.g. 0x120) are dropped")
    }

    func testCleanedEmptyIsEmpty() {
        XCTAssertEqual(NSEvent.ModifierFlags([]).cleaned(), [])
    }

    private let escapeKeycode: UInt32 = 53 // kVK_Escape

    private let keycodeMap: [Character: UInt32] = [
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
}
