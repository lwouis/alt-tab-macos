import XCTest
import ShortcutRecorder

final class CustomRecorderControlTests: XCTestCase {
    func testIsShortcutAcceptable() {
        // .accepted
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⇧⇥")!), .accepted)
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut", .global, .up)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌥")!), .accepted)
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts

        // .modifiersOnlyButContainsKeycode
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⇧")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘e")!), .modifiersOnlyButContainsKeycode)

        // .reservedByMacos
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘")!), .accepted) // ⌘⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⌘⇧")!), .accepted) // ⌘⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⌘⌃⇧")!), .accepted) // ⌘⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⌥")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⌥⇧")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⇧⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⌥⌃⇧")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⌃⇧⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("cancelShortcut", Shortcut(keyEquivalent: "⌘⇧⎋")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⇧⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("cancelShortcut", Shortcut(keyEquivalent: "⌘⇧⌃⎋")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⇧⌃⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("cancelShortcut", Shortcut(keyEquivalent: "⌘⎋")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⎋

        // .conflictWithExistingShortcut
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("vimCycleRight", Shortcut(keyEquivalent: "l")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⇧⇥")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("vimCycleLeft", Shortcut(keyEquivalent: "h")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "hideShowAppShortcut"))
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⇥")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut"))
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: "⇧")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "previousWindowShortcut"))

        // alt + shift+tab / alt+shift + tab => pressing tab is ambiguous which one should trigger
        ControlsTab.shortcuts["previousWindowShortcut"] = ATShortcut(Shortcut(keyEquivalent: "p")!, "previousWindowShortcut", .local, .down)
        ControlsTab.shortcuts["nextWindowShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⇧⇥")!, "nextWindowShortcut2", .global, .down)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌥⇧")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut2"))
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts

        // alt + shift / alt+command + shift => doesn't work if allowed
        ControlsTab.shortcuts["nextWindowShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⇧")!, "nextWindowShortcut", .global, .down)
        ControlsTab.shortcuts["holdShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut2", .global, .up)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⇧")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut"))
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts

        // Shortcut 1: alt + tab / Shortcut 2: alt + command+tab => works if allowed
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⌘⇥")!), .accepted)
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts

        // Shortcut 1: alt + tab / Shortcut 2: alt+command + tab [assign Shortcut 2 last] => works if allowed
        ControlsTab.shortcuts["holdShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut2", .global, .up)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⇥")!), .accepted)
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts

        // Shortcut 1: alt + tab / Shortcut 2: alt+command + tab [assign Shortcut 1 last] => works if allowed
        ControlsTab.shortcuts["holdShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut2", .global, .up)
        ControlsTab.shortcuts["nextWindowShortcut"] = ATShortcut(Shortcut(keyEquivalent: "t")!, "nextWindowShortcut", .global, .down)
        ControlsTab.shortcuts["nextWindowShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⇥")!, "nextWindowShortcut2", .global, .down)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: "⇥")!), .accepted)
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
    }
}
