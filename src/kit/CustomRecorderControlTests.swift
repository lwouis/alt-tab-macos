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

    /// Issue #5455. The reporter's configuration (from their `defaults read`): S1 = hold ⌘ + press ⎋,
    /// S2 = hold ⌥ + press `. That already double-assigns ⌘⎋: Cancel is ⎋, and under S1's own ⌘ hold
    /// that is S1's trigger. Nothing re-validates a saved configuration, so the pair sits there. Their
    /// config predates a validation hole being plugged, but note the UI can still produce such a pair:
    /// "Unassign existing shortcut and continue" unassigns the ONE conflict it named, then applies the
    /// edit without re-checking, so a second conflict from that same edit lands silently.
    ///
    /// Giving another shortcut a ⌘ hold, which is how you reach ⌘` from there, recomputes Cancel under
    /// ⌘, lands on that same ⌘⎋, and was rejected with "already assigned to Shortcut 1 - Trigger": a
    /// collision the edit doesn't introduce, naming a shortcut the user isn't touching and can only
    /// resolve by unassigning it. Only a collision the edit actually introduces should be reported.
    func testIsShortcutAcceptable_preExistingCollisionDoesNotBlockAnUnrelatedEdit() {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘")!, "holdShortcut", .global, .up, 0)
        ControlsTab.shortcuts["nextWindowShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘⎋")!, "nextWindowShortcut", .global, .down)
        ControlsTab.shortcuts["nextWindowShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌥`")!, "nextWindowShortcut2", .global, .down)
        defer { ControlsTab.shortcuts = ControlsTab.defaultShortcuts }
        // the edit the reporter couldn't make: S2's hold ⌥ -> ⌘, giving them ⌘`
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut2", Shortcut(keyEquivalent: "⌘")!), .accepted)
        // a collision the edit DOES introduce is still reported: ⌥⎋ is free today, so giving S2 the
        // press ⎋ newly clashes with Cancel under S2's own ⌥ hold
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("nextWindowShortcut2", Shortcut(keyEquivalent: "⎋")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "cancelShortcut"))
    }

    /// Same as above for the modifiers-only branch of `chordsCollide`, where the pre-existing pair
    /// collides by superset rather than by equal chords: S1 = ⌥+⇧ and S2 = ⌘⌥+⇧ already satisfy each
    /// other. Widening S2's hold keeps that pair colliding exactly as it was, so it must not be
    /// reported; a superset collision the edit does introduce still must be.
    func testIsShortcutAcceptable_preExistingModifiersOnlyCollisionDoesNotBlockAnUnrelatedEdit() {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        // it is ⇧, which under S1's ⌥ hold would be a second pre-existing collision, muddying the case
        ControlsTab.shortcuts["previousWindowShortcut"] = nil
        ControlsTab.shortcuts["nextWindowShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌥⇧")!, "nextWindowShortcut", .global, .down)
        ControlsTab.shortcuts["holdShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut2", .global, .up, 1)
        ControlsTab.shortcuts["nextWindowShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥⇧")!, "nextWindowShortcut2", .global, .down)
        defer { ControlsTab.shortcuts = ControlsTab.defaultShortcuts }
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut2", Shortcut(keyEquivalent: "⌘⌥⌃")!), .accepted)
        // S3 = ⌃+⇧ is uninvolved in that pair and collides with nothing today, so widening its hold to
        // ⌥⌃, which makes its ⇧ press a superset of S1's ⌥⇧, is a collision the edit does introduce
        ControlsTab.shortcuts["holdShortcut3"] = ATShortcut(Shortcut(keyEquivalent: "⌃")!, "holdShortcut3", .global, .up, 2)
        ControlsTab.shortcuts["nextWindowShortcut3"] = ATShortcut(Shortcut(keyEquivalent: "⌃⇧")!, "nextWindowShortcut3", .global, .down)
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut3", Shortcut(keyEquivalent: "⌥⌃")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut"))
    }

    /// `chordsCollide` has to catch a modifiers-only pair whichever way the containment runs. The 2
    /// tests above only ever make the CANDIDATE's chord the superset, so they pass just as well with
    /// the other direction dropped. Here the candidate's chord is the subset instead: S1 = ⌘⌥+⇧ and
    /// S2 = ⌃+⇧ collide with nothing, and narrowing S2's hold to ⌘ makes its ⇧ press ⌘⇧, which S1's
    /// ⌘⌥⇧ already satisfies.
    func testIsShortcutAcceptable_modifiersOnlyCollidesWhenTheCandidateChordIsTheSubset() {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        ControlsTab.shortcuts["previousWindowShortcut"] = nil
        ControlsTab.shortcuts["holdShortcut3"] = nil
        ControlsTab.shortcuts["holdShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥")!, "holdShortcut", .global, .up, 0)
        ControlsTab.shortcuts["nextWindowShortcut"] = ATShortcut(Shortcut(keyEquivalent: "⌘⌥⇧")!, "nextWindowShortcut", .global, .down)
        ControlsTab.shortcuts["holdShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌃")!, "holdShortcut2", .global, .up, 1)
        ControlsTab.shortcuts["nextWindowShortcut2"] = ATShortcut(Shortcut(keyEquivalent: "⌃⇧")!, "nextWindowShortcut2", .global, .down)
        defer { ControlsTab.shortcuts = ControlsTab.defaultShortcuts }
        XCTAssertEqual(CustomRecorderControlTestable.isShortcutAcceptable("holdShortcut2", Shortcut(keyEquivalent: "⌘")!),
            .conflictWithExistingShortcut(shortcutAlreadyAssigned: "nextWindowShortcut"))
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
