import XCTest
import Carbon.HIToolbox.Events

/// Pins `NativeHotkeyResolver.resolve` against the configurations that historically tripped
/// issue #5653 (intermittent native ⌘⇥ override on launch).
///
/// Groups: A repro case (⌘⇥ + ⌘⇧⇥ with hold ⌘ + ⌘⇧) · B single ⌘⇥ pairing ·
/// C ⌘\` only · D default option · E empty.
final class NativeHotkeyResolverTests: XCTestCase {
    private func snap(_ mods: Int, _ key: Int) -> ShortcutSnapshot {
        ShortcutSnapshot(modifiers: UInt32(mods), keyCode: UInt32(key))
    }

    // MARK: - A. Issue #5653 — ⌘⇥ + ⌘⇧⇥ with hold ⌘ + ⌘⇧

    /// With both ⌘⇥ and ⌘⇧⇥ bound (and the matching ⌘ + ⌘⇧ hold-shortcuts present), both native
    /// switchers must be disabled — even though the ⌘⇥ snapshot matches *two* native predicates
    /// (`.commandTab` exact, `.commandShiftTab` via combined hold). The pre-fix `.first { … }`
    /// over the predicate dictionary would intermittently drop `.commandTab` here.
    func testCommandTabAndCommandShiftTabBothDisableNativeSwitchers() {
        let result = NativeHotkeyResolver.resolve(
            shortcuts: [snap(cmdKey, kVK_Tab), snap(cmdKey | shiftKey, kVK_Tab)],
            holdShortcutModifiers: [UInt32(cmdKey), UInt32(cmdKey | shiftKey)])
        XCTAssertEqual(result.disable, [.commandTab, .commandShiftTab])
        XCTAssertEqual(result.enable, [.commandKeyAboveTab])
    }

    /// Within one process the result must be stable across repeated calls on identical inputs.
    /// (The original cross-process flakiness — different Swift dictionary hash seeds picking a
    /// different `.first` predicate per launch — was the user-visible bug.)
    func testResolutionIsDeterministicAcrossRepeatedCalls() {
        let shortcuts = [snap(cmdKey, kVK_Tab), snap(cmdKey | shiftKey, kVK_Tab)]
        let holds = [UInt32(cmdKey), UInt32(cmdKey | shiftKey)]
        let first = NativeHotkeyResolver.resolve(shortcuts: shortcuts, holdShortcutModifiers: holds)
        for _ in 0..<50 {
            let r = NativeHotkeyResolver.resolve(shortcuts: shortcuts, holdShortcutModifiers: holds)
            XCTAssertEqual(r.disable, first.disable)
            XCTAssertEqual(r.enable, first.enable)
        }
    }

    // MARK: - B. Single ⌘⇥ — still pairs with ⌘⇧⇥

    /// With only ⌘⇥ bound, native ⌘⇧⇥ (reverse switcher) must also be disabled so it doesn't fire
    /// when the user presses shift while the switcher is open.
    func testCommandTabAloneAlsoDisablesReverseSwitcher() {
        let result = NativeHotkeyResolver.resolve(
            shortcuts: [snap(cmdKey, kVK_Tab)],
            holdShortcutModifiers: [UInt32(cmdKey)])
        XCTAssertEqual(result.disable, [.commandTab, .commandShiftTab])
        XCTAssertEqual(result.enable, [.commandKeyAboveTab])
    }

    // MARK: - C. ⌘` alone — disables only that hotkey

    /// Binding ⌘\` overrides the native "key above Tab" hotkey but leaves both switcher hotkeys
    /// alone. No cross-talk between Tab and grave key predicates.
    func testCommandKeyAboveTabAloneDisablesOnlyThatHotkey() {
        let result = NativeHotkeyResolver.resolve(
            shortcuts: [snap(cmdKey, kVK_ANSI_Grave)],
            holdShortcutModifiers: [UInt32(cmdKey)])
        XCTAssertEqual(result.disable, [.commandKeyAboveTab])
        XCTAssertEqual(result.enable, [.commandTab, .commandShiftTab])
    }

    // MARK: - D. Default option config — no native switcher overlap

    /// AltTab's default trigger (⌥⇥ / hold ⌥) doesn't overlap any native command-tab hotkey, so
    /// every native hotkey stays enabled — AltTab coexists with the system's native switcher.
    func testOptionTabDoesNotOverrideNativeSwitchers() {
        let result = NativeHotkeyResolver.resolve(
            shortcuts: [snap(optionKey, kVK_Tab)],
            holdShortcutModifiers: [UInt32(optionKey)])
        XCTAssertEqual(result.disable, [])
        XCTAssertEqual(result.enable, [.commandTab, .commandShiftTab, .commandKeyAboveTab])
    }

    // MARK: - E. No shortcuts at all — nothing to override

    /// Defensive: with no shortcuts configured, no native hotkey is disabled.
    func testEmptyConfigReleasesAllNativeHotkeys() {
        let result = NativeHotkeyResolver.resolve(shortcuts: [], holdShortcutModifiers: [])
        XCTAssertEqual(result.disable, [])
        XCTAssertEqual(result.enable, [.commandTab, .commandShiftTab, .commandKeyAboveTab])
    }
}

/// Pins `NativeHotkeyOwnership` against issue #5455: AltTab must switch back on only the native
/// hotkeys it switched off itself, never one the user turned off in System Settings.
final class NativeHotkeyOwnershipTests: XCTestCase {
    private let allOn: (CGSSymbolicHotKey) -> Bool = { _ in true }
    private let allOff: (CGSSymbolicHotKey) -> Bool = { _ in false }

    /// The regression: the user turned ⌘` off themselves, AltTab never claimed it, so releasing the
    /// hotkeys AltTab doesn't need must not switch it back on.
    func testDoesNotEnableAHotkeyTheUserDisabled() {
        var ownership = NativeHotkeyOwnership()
        XCTAssertEqual(ownership.claim([.commandKeyAboveTab], allOff), [])
        XCTAssertEqual(ownership.release([.commandTab, .commandShiftTab, .commandKeyAboveTab]), [])
    }

    /// The normal path: AltTab switches ⌘⇥ off, then puts it back when it no longer needs it.
    func testRestoresOnlyWhatItDisabled() {
        var ownership = NativeHotkeyOwnership()
        XCTAssertEqual(ownership.claim([.commandTab], allOn), [.commandTab])
        XCTAssertEqual(ownership.disabledByAltTab, [.commandTab])
        XCTAssertEqual(ownership.release([.commandTab, .commandShiftTab, .commandKeyAboveTab]), [.commandTab])
        XCTAssertEqual(ownership.disabledByAltTab, [])
    }

    /// `toggleNativeCommandTabIfNeeded` runs on every shortcut edit, so claiming must be idempotent:
    /// a hotkey already owned isn't re-issued (and `isEnabled` reads false for it by then anyway).
    func testClaimingAnAlreadyOwnedHotkeyIsANoop() {
        var ownership = NativeHotkeyOwnership()
        _ = ownership.claim([.commandTab], allOn)
        XCTAssertEqual(ownership.claim([.commandTab], allOff), [])
        XCTAssertEqual(ownership.disabledByAltTab, [.commandTab])
    }

    /// Releasing a hotkey AltTab owns must only report it once; a second release is a no-op, so
    /// quitting after the settings already released it doesn't switch anything on.
    func testReleasingTwiceOnlyRestoresOnce() {
        var ownership = NativeHotkeyOwnership()
        _ = ownership.claim([.commandTab], allOn)
        XCTAssertEqual(ownership.release([.commandTab]), [.commandTab])
        XCTAssertEqual(ownership.release([.commandTab]), [])
    }

    /// A partial release (the settings dropping ⌘⇥ while ⌘` stays bound) leaves the other hotkey
    /// owned, so quitting still restores it.
    func testPartialReleaseKeepsOtherHotkeysOwned() {
        var ownership = NativeHotkeyOwnership()
        _ = ownership.claim([.commandTab, .commandKeyAboveTab], allOn)
        XCTAssertEqual(ownership.release([.commandTab]), [.commandTab])
        XCTAssertEqual(ownership.disabledByAltTab, [.commandKeyAboveTab])
        XCTAssertEqual(ownership.release(Set(CGSSymbolicHotKey.allCases)), [.commandKeyAboveTab])
    }

    /// Mixed state: of the two AltTab asks for, only the one the user had on is claimed.
    func testClaimsOnlyTheHotkeysThatWereOn() {
        var ownership = NativeHotkeyOwnership()
        let claimed = ownership.claim([.commandTab, .commandKeyAboveTab], { $0 == .commandTab })
        XCTAssertEqual(Set(claimed), [.commandTab])
        XCTAssertEqual(ownership.disabledByAltTab, [.commandTab])
    }
}
