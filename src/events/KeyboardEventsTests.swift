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

    // alt-down > tab-down > tab-up > (alt-up never lands) > tab-down
    // The first pair's release is lost, so its session is still open when the second pair's tab-down
    // arrives. That release must be honoured on the tile the user was looking at, BEFORE the tab-down
    // cycles: honoured after, the focus commits one tile too far, and the alt-tabs after it ping-pong
    // against a window that was never picked, seen live.
    func testLostHoldReleaseIsSettledBeforeTheNextSummonCycles() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut"])
        ModifierFlags.current = []
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered,
                       ["nextWindowShortcut", "holdShortcut", "nextWindowShortcut", "holdShortcut"])
    }

    func testRecordedReleaseSettlesTheSessionOpenedByItsDelayedHotkey() throws {
        resetState()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down,
                            nil, nil, false, nil, true)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered, ["nextWindowShortcut", "holdShortcut"])
    }

    func testInputLogSeparatesTwoPairsButKeepsTwoTabsUnderOneHoldTogether() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))

        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        XCTAssertFalse(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
    }

    func testInputLogDoesNotClaimAKeyDownFromBeforeRegistrationChanged() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        XCTAssertFalse(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
    }

    func testInputLogDoesNotLetALateKeyDownPoisonTheNextGesture() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        XCTAssertFalse(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
    }

    func testInputLogIgnoresAutoRepeatsSoAHeldTabDoesNotShiftLaterPairs() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        // a held ⌥⇥: one press, then the OS's repeats, then the release. Carbon fires once and claims once
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        for _ in 0..<5 { ModifierReleaseLog.recordKeyDown(48, [.option], isARepeat: true) }
        XCTAssertFalse(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
        ModifierReleaseLog.record([])
        // two complete pairs delayed behind a stall must each pair with their own release
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
    }

    func testInputLogDropsAnUnmatchedClaimAtTheGestureRelease() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        XCTAssertFalse(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
        ModifierReleaseLog.record([])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
    }

    func testInputLogRecordsOnlySwitchingChordsSoTypingCannotEvictADelayedHotkey() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option])
        ModifierReleaseLog.recordKeyDown(48, [.option])
        ModifierReleaseLog.record([])
        // a sentence of capitals while main is stalled: well past the log's capacity if it were recorded
        for _ in 0..<40 {
            ModifierReleaseLog.record([.shift])
            ModifierReleaseLog.recordKeyDown(0, [.shift])
            ModifierReleaseLog.record([])
        }
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
    }

    func testInputLogMatchesTheChordWithCapsLockLit() throws {
        let option = CarbonModifierFlags(1 << 11)
        let tab = ModifierReleaseLog.Chord(keyCode: 48, modifiers: option)
        ModifierReleaseLog.setSwitchingChords([tab])
        ModifierReleaseLog.record([.option, .capsLock])
        ModifierReleaseLog.recordKeyDown(48, [.option, .capsLock])
        ModifierReleaseLog.record([.capsLock])
        XCTAssertTrue(ModifierReleaseLog.claimRelease(after: tab, holdModifiers: option))
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
        ModifierReleaseLog.reset()
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
