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
