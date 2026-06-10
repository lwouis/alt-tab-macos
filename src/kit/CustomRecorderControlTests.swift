import XCTest
import ShortcutRecorder

final class CustomRecorderControlTests: XCTestCase {
    func testIsShortcutAcceptable_accepted() {
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⇧⇥")!), .accepted)
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut", .global, .up)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌥")!), .accepted)
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌥")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⇧")!), .accepted)
        ControlsTab.shortcuts["previousWindowShortcut"] = nil
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⇧")!), .accepted)
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
    }

    func testIsShortcutAcceptable_modifiersOnlyButContainsKeycode() {
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⇧")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘e")!), .modifiersOnlyButContainsKeycode)
    }

    func testIsShortcutAcceptable_conflictWithExistingShortcut() {
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("vimCycleRight", Shortcut(keyEquivalent: "l")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⇧⇥")!), .accepted)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("vimCycleLeft", Shortcut(keyEquivalent: "h")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "hideShowAppShortcut"))
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⇥")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut"))
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: "⇧")!), .conflictWithExistingShortcut(shortcutAlreadyAssigned: "previousWindowShortcut"))
    }

    /// Regression: S1 = ⌥+Tab, S2 = ⌘+Tab. Changing S2's *hold* from ⌘ to ⌥ makes it ⌥+Tab, which must
    /// conflict with S1. The registry here mirrors PRODUCTION, where `nextWindowShortcut` is stored
    /// COMBINED (hold ∪ key) — unlike `defaultShortcuts`, which stores it raw, which is precisely why
    /// the existing tests never exercised this. Without stripping S2's current ⌘ hold before applying
    /// the new ⌥, the chord is mis-computed as ⌥⌘+Tab and the conflict is silently accepted.
    func testIsShortcutAcceptable_holdChangeStripsOldHoldFromCombinedNextWindow() {
        ControlsTab.shortcuts = [
            "holdShortcut": ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut", .global, .up, 0),
            "nextWindowShortcut": ATShortcut(Shortcut(keyEquivalent: "⌥⇥")!, "nextWindowShortcut", .global, .down),
            "holdShortcut2": ATShortcut(Shortcut(keyEquivalent: "⌘")!, "holdShortcut2", .global, .up, 1),
            "nextWindowShortcut2": ATShortcut(Shortcut(keyEquivalent: "⌘⇥")!, "nextWindowShortcut2", .global, .down),
        ]
        defer { ControlsTab.shortcuts = ControlsTab.defaultShortcuts }
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut2", Shortcut(keyEquivalent: "⌥")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut"))
        // The mirror case: changing the hold to something that does NOT collide stays accepted.
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut2", Shortcut(keyEquivalent: "⌃")!), .accepted)
    }

    /// Regression: S1 = ⌃+→, enable "Select windows using arrow keys", accept the dialog's
    /// "Unassign and continue" (clears S1's press, keeps its ⌃ hold), then re-record → as the
    /// press. Under S1's OWN hold, → is ambiguous (cycle vs select), so it must be rejected —
    /// but `oldCombinationsExcludingTargetOfCandidate` excluded the same-index hold for a press
    /// candidate, so arrows were only combined with the OTHER shortcuts' holds. With every
    /// default hold being ⌥, the ⌥+→ variant was caught by luck via Shortcut 2's identical hold,
    /// while ⌃+→ (a hold no other shortcut shares) recorded silently with no conflict dialog.
    func testIsShortcutAcceptable_pressConflictsWithLocalShortcutsUnderItsOwnHold() {
        // the post-"unassign and continue" state: the press is gone from the registry, the hold remains
        ControlsTab.shortcuts["nextWindowShortcut"] = nil
        defer { ControlsTab.shortcuts = ControlsTab.defaultShortcuts }
        // ⌥ hold: was already caught pre-fix, but only via holdShortcut2's identical ⌥ — pin it
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: "→")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "→"))
        // ⌃ hold, shared with no other shortcut: the conflict must be found via S1's own hold
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌃")!, "holdShortcut", .global, .up, 0)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: "→")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "→"))
        // same mechanism covers the static locals (Space = focus selected window)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: " ")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "focusWindowShortcut"))
        // a press that collides with nothing stays accepted
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut", Shortcut(keyEquivalent: "t")!), .accepted)
    }

    func testIsShortcutAcceptable_reservedByMacos() {
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⌘⇧")!), .accepted) // ⌘⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("previousWindowShortcut", Shortcut(keyEquivalent: "⌘⌃⇧")!), .accepted) // ⌘⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⌥")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⌥⇧")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⇧⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘⌥⌃⇧")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⌃⇧⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("cancelShortcut", Shortcut(keyEquivalent: "⌘⇧⎋")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⇧⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("cancelShortcut", Shortcut(keyEquivalent: "⌘⇧⌃⎋")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⇧⌃⎋
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("cancelShortcut", Shortcut(keyEquivalent: "⌘⎋")!), .reservedByMacos(shortcutUsingEscape: "cancelShortcut")) // ⌘⌥⎋

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

    // Issue #5585: previously, binding holdShortcut to ⌘ was rejected on macOS 26+ because
    // ⌘+cancelShortcut(=⎋) collided with Game Overlay. With the cghid event tap in
    // KeyboardEvents absorbing Esc at HID level (before Game Overlay's hook), we can bind ⌘⎋
    // freely.
    func testIsShortcutAcceptable_cmdHoldShortcutNoLongerBlockedByGameOverlay() {
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut", Shortcut(keyEquivalent: "⌘")!), .accepted)
    }

    // MARK: - isWellFormedCandidateId

    /// Regression guard for the conflict dialog that silently stopped appearing under the recycled
    /// `ShortcutEditor`: the recorder handed the kernel a frozen placeholder id (`"nextWindowShortcut0"`,
    /// whose `nameToIndex` is -1), which matched no shortcut, so `isShortcutAcceptable` returned
    /// `.accepted` and no dialog showed. `isWellFormedCandidateId` rejects exactly that shape — and a
    /// `#if DEBUG` assert in `isShortcutAcceptable` now trips loudly if such an id ever reaches it.
    func testIsWellFormedCandidateId() {
        // hold/next ids must resolve to an in-range shortcut index (shortcutCount == 3 in the mock).
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("holdShortcut"))         // index 0
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("nextWindowShortcut"))    // index 0
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("nextWindowShortcut2"))   // index 1
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("holdShortcut3"))         // index 2
        // The regressing placeholders: trailing "0" → nameToIndex -1 → out of range.
        XCTAssertFalse(CustomRecorderControlTestable.isWellFormedCandidateId("nextWindowShortcut0"))
        XCTAssertFalse(CustomRecorderControlTestable.isWellFormedCandidateId("holdShortcut0"))
        // Beyond shortcutCount is also malformed.
        XCTAssertFalse(CustomRecorderControlTestable.isWellFormedCandidateId("nextWindowShortcut4"))  // index 3
        // Static "when active" / arrow / vim ids are well-formed regardless of any index.
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("cancelShortcut"))
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("←"))
        XCTAssertTrue(CustomRecorderControlTestable.isWellFormedCandidateId("vimCycleLeft"))
    }

    // MARK: - combinedModifiersMatch

    // Per the kernel's doc-comment: the function checks whether two modifier sets match once each is
    // OR-ed with the configured holdShortcut's modifiers. This is what lets the matcher recognize a
    // chord like commandShiftTab whose modifiers are physically split between a holdShortcut (e.g.
    // ⌘⌥) and a local shortcut (e.g. ⇧).

    /// A modifier set OR-ed with the hold modifiers matches itself — the trivial case keyed by the
    /// hold-modifier union, not by raw equality.
    func testCombinedModifiersMatchEqualToItself() {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        let modifiers = Shortcut(keyEquivalent: "⌥")!.carbonModifierFlags
        XCTAssertTrue(CustomRecorderControlTestable.combinedModifiersMatch(modifiers, modifiers))
    }

    /// With holdShortcut at ⌥, two physically different modifier sets that produce the same union
    /// (`holdMods | x`) for some hold slot match. Here both ⌘⌥ and ⌥ collapse to ⌘⌥ once OR-ed
    /// with the ⌘⌥ hold modifiers from slot 1.
    func testCombinedModifiersMatchUnifiesWhenHoldModifiersDominate() {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut", .global, .up)
        defer { ControlsTab.shortcuts = ControlsTab.defaultShortcuts }
        let cmdOpt = Shortcut(keyEquivalent: "⌘⌥")!.carbonModifierFlags
        let opt = Shortcut(keyEquivalent: "⌥")!.carbonModifierFlags
        XCTAssertTrue(CustomRecorderControlTestable.combinedModifiersMatch(cmdOpt, opt),
            "⌘⌥ | ⌘⌥ == ⌘⌥, and ⌘⌥ | ⌥ == ⌘⌥ — both equal, so they match.")
    }

    /// Disjoint modifier sets that can't be unified by any holdShortcut union do not match.
    /// We clear every hold slot first so the test isn't sensitive to which slots the
    /// defaults populate.
    func testCombinedModifiersMatchRejectsDisjointModifiers() {
        let original = ControlsTab.shortcuts
        for i in 0..<Preferences.maxShortcutCount {
            ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", i)] = nil
        }
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌥")!, "holdShortcut", .global, .up)
        defer { ControlsTab.shortcuts = original }
        let cmd = Shortcut(keyEquivalent: "⌘")!.carbonModifierFlags
        let ctrl = Shortcut(keyEquivalent: "⌃")!.carbonModifierFlags
        // ⌥|⌘ == ⌘⌥, ⌥|⌃ == ⌃⌥ — different, so no match.
        XCTAssertFalse(CustomRecorderControlTestable.combinedModifiersMatch(cmd, ctrl))
    }

    /// When no holdShortcut is configured at any slot, the function returns false — no slot can
    /// produce a union to compare against.
    func testCombinedModifiersMatchReturnsFalseWhenNoHoldShortcuts() {
        let original = ControlsTab.shortcuts
        for i in 0..<Preferences.maxShortcutCount {
            ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", i)] = nil
        }
        defer { ControlsTab.shortcuts = original }
        let opt = Shortcut(keyEquivalent: "⌥")!.carbonModifierFlags
        XCTAssertFalse(CustomRecorderControlTestable.combinedModifiersMatch(opt, opt))
    }

    // Note on `Shortcut.keyEquivalent` (defined in `CustomRecorderControlTestable.swift`):
    // It's used in production by `ControlsTab.shortcutSummary` (not just "for testing" as the old
    // comment claimed — see the corrected doc-comment on the getter). It shows as 0% coverage
    // here because the getter calls ShortcutRecorder's `readableStringRepresentation(isASCII:)`
    // which throws `NSInternalInconsistencyException: Unable to find bundle with resources` when
    // the framework's bundle isn't loaded — i.e. in the unit-test target. Testing it would
    // require either loading the ShortcutRecorder bundle in test setup or extracting the
    // formatting logic so it doesn't depend on `readableStringRepresentation`. Left alone here
    // to avoid that bigger refactor; flagged in `CustomRecorderControlSpecs.md`.
}
