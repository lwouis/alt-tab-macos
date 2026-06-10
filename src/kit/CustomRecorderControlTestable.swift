import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControlTestable {
    /// A `holdShortcut`/`nextWindowShortcut` candidate id must resolve to an in-range shortcut index;
    /// every other id (the static "when active" shortcuts, arrow, vim) is well-formed by definition.
    /// This is the contract the recycled `ShortcutEditor` must uphold: the id handed to the conflict
    /// check is the bound preference key, not a stale placeholder. The regression that hid the
    /// conflict dialog was exactly a malformed id — the recorder's frozen `"nextWindowShortcut0"`,
    /// whose `nameToIndex` is -1 — silently matching nothing and returning `.accepted`.
    static func isWellFormedCandidateId(_ id: String) -> Bool {
        guard id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut") else { return true }
        return (0..<Preferences.shortcutCount).contains(Preferences.nameToIndex(id))
    }

    static func isShortcutAcceptable(_ candidateId: String, _ candidateShortcut: Shortcut) -> ShortcutAcceptance {
        assert(isWellFormedCandidateId(candidateId), "malformed candidateId '\(candidateId)' reached the conflict check — recycled editor id/identifier drift?")
        if let currentShortcutWithSameId = ControlsTab.shortcuts[candidateId]?.shortcut,
           candidateShortcut.carbonKeyCode == currentShortcutWithSameId.carbonKeyCode && candidateShortcut.carbonModifierFlags == currentShortcutWithSameId.carbonModifierFlags {
            return .accepted
        }
        if candidateId.starts(with: "holdShortcut") && candidateShortcut.keyCode != .none {
            return .modifiersOnlyButContainsKeycode
        }
        let newCombos = newCombinationsFromCandidate(candidateId, candidateShortcut)
        let oldCombos = oldCombinationsExcludingTargetOfCandidate(candidateId)
        // TODO: a user can assign a shortcut that's both .conflictWithExistingShortcut and .reservedByMacos
        // It's a mess to deal with. Current implem may let them bypass isReservedByMacos. Would be nice to think about what UX to do here
        if let alreadyAssigned = isAlreadyUsedByAnotherShortcut(newCombos, oldCombos) {
            return .conflictWithExistingShortcut(shortcutAlreadyAssigned: alreadyAssigned)
        }
        if let shortcutUsingEscape = isReservedByMacos(newCombos) {
            return .reservedByMacos(shortcutUsingEscape: shortcutUsingEscape)
        }
        return .accepted
    }

    static func newCombinationsFromCandidate(_ candidateId: String, _ candidateShortcut: Shortcut) -> [(String, Shortcut)] {
        var combos = [(String, Shortcut)]()
        for atShortcut in ControlsTab.shortcuts.values {
            guard atShortcut.id != candidateId
                      && !((candidateId.starts(with: "holdShortcut") || candidateId.starts(with: "nextWindowShortcut")) && (atShortcut.id.starts(with: "holdShortcut") || atShortcut.id.starts(with: "nextWindowShortcut")) && Preferences.nameToIndex(candidateId) != Preferences.nameToIndex(atShortcut.id))
                      && !(atShortcut.shortcut.keyCode == .none && atShortcut.shortcut.modifierFlags == []) else { continue }
            // candidate is holdShortcut
            if candidateId.starts(with: "holdShortcut") {
                // combine the candidate's (new) hold modifiers with a local shortcut, which is stored raw
                if !atShortcut.id.starts(with: "holdShortcut") && !atShortcut.id.starts(with: "nextWindowShortcut") {
                    combos.append((atShortcut.id, Shortcut(code: atShortcut.shortcut.keyCode, modifierFlags: [candidateShortcut.modifierFlags, atShortcut.shortcut.modifierFlags], characters: nil, charactersIgnoringModifiers: nil)))
                // combine with the nextWindowShortcut of the same index. That shortcut is stored COMBINED
                // with the CURRENT (old) hold, so strip the old hold before applying the candidate's new
                // hold — otherwise changing the hold (e.g. ⌘→⌥) leaks the old modifier (⌥⌘⇥ instead of
                // ⌥⇥) and a real conflict is missed. (No-op when nextWindow is stored raw, e.g. in tests.)
                } else if atShortcut.id.starts(with: "nextWindowShortcut") && Preferences.nameToIndex(candidateId) == Preferences.nameToIndex(atShortcut.id) {
                    let oldHoldModifiers = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", Preferences.nameToIndex(candidateId))]?.shortcut.modifierFlags ?? []
                    combos.append((atShortcut.id, Shortcut(code: atShortcut.shortcut.keyCode, modifierFlags: [candidateShortcut.modifierFlags, atShortcut.shortcut.modifierFlags.subtracting(oldHoldModifiers)], characters: nil, charactersIgnoringModifiers: nil)))
                }
            // candidate is nextWindowShortcut
            } else if candidateId.starts(with: "nextWindowShortcut") {
                // combine with holdShortcut of same index
                if (atShortcut.id.starts(with: "holdShortcut") && Preferences.nameToIndex(candidateId) == Preferences.nameToIndex(atShortcut.id)) {
                    combos.append((candidateId, Shortcut(code: candidateShortcut.keyCode, modifierFlags: [candidateShortcut.modifierFlags, atShortcut.shortcut.modifierFlags], characters: nil, charactersIgnoringModifiers: nil)))
                }
            // candidate is a local shortcut
            } else {
                // combine with every holdShortcut
                if atShortcut.id.starts(with: "holdShortcut") {
                    combos.append((candidateId, Shortcut(code: candidateShortcut.keyCode, modifierFlags: [candidateShortcut.modifierFlags, atShortcut.shortcut.modifierFlags], characters: nil, charactersIgnoringModifiers: nil)))
                }
            }
        }
        return combos
    }

    /// Whether `existingId`'s chords are already represented in `newCombinationsFromCandidate`,
    /// so it must be left out of the "old" combos. For the candidate's same-index trigger pair:
    /// the `nextWindowShortcut` always (its chord is what's being recomputed, whether the candidate
    /// is the hold or the press), but the `holdShortcut` only when the candidate replaces it. A
    /// press edit keeps its hold, and that hold still combines with the local shortcuts (arrows /
    /// vim / statics) — excluding it meant e.g. press=→ with arrow-keys selection enabled was only
    /// flagged when ANOTHER shortcut shared the same hold modifiers (the default double-⌥ holds
    /// caught ⌥+→ by luck while ⌃+→ recorded with no conflict dialog).
    static func isRecomputedInNewCombinations(_ candidateId: String, _ existingId: String) -> Bool {
        guard (candidateId.starts(with: "holdShortcut") || candidateId.starts(with: "nextWindowShortcut"))
                  && (existingId.starts(with: "holdShortcut") || existingId.starts(with: "nextWindowShortcut"))
                  && Preferences.nameToIndex(candidateId) == Preferences.nameToIndex(existingId) else { return false }
        return existingId.starts(with: "nextWindowShortcut") || candidateId.starts(with: "holdShortcut")
    }

    static func oldCombinationsExcludingTargetOfCandidate(_ candidateId: String) -> [(String, Shortcut)] {
        var holds = [ATShortcut]()
        var nonHolds = [ATShortcut]()
        for atShortcut in ControlsTab.shortcuts.values {
            guard !isRecomputedInNewCombinations(candidateId, atShortcut.id)
                      && !(atShortcut.shortcut.keyCode == .none && atShortcut.shortcut.modifierFlags == []) else { continue }
            if atShortcut.id.starts(with: "holdShortcut") {
                holds.append(atShortcut)
            } else {
                nonHolds.append(atShortcut)
            }
        }
        var combos = [(String, Shortcut)]()
        for hold in holds {
            for nonHold in nonHolds {
                guard !nonHold.id.starts(with: "nextWindowShortcut") || Preferences.nameToIndex(nonHold.id) == Preferences.nameToIndex(hold.id) else { continue }
                combos.append((nonHold.id, Shortcut(code: nonHold.shortcut.keyCode, modifierFlags: [hold.shortcut.modifierFlags, nonHold.shortcut.modifierFlags], characters: nil, charactersIgnoringModifiers: nil)))
            }
        }
        return combos
    }

    static func isReservedByMacos(_ newCombinationsFromCandidate: [(String, Shortcut)] ) -> String? {
        for r in (ReservedMacosShortcut.allCases.map { $0.basicShortcut }) {
            for c in newCombinationsFromCandidate {
                if c.1.carbonKeyCode == r.carbonKeyCode && c.1.carbonModifierFlags == r.carbonModifierFlags {
                    return c.0
                }
            }
        }
        return nil
    }

    static func isAlreadyUsedByAnotherShortcut(_ newCombos: [(String, Shortcut)] , _ oldCombos: [(String, Shortcut)]) -> String? {
        for newCombo in newCombos {
            for oldCombo in oldCombos {
                guard !(newCombo.0 == oldCombo.0) else { continue }
                if (newCombo.1.keyCode == oldCombo.1.keyCode && newCombo.1.modifierFlags == oldCombo.1.modifierFlags)
                    // special case when 2 nextWindowShortcuts are modifiers-only (e.g. S1: alt + shift, S2: alt+command + shift)
                    // they will conflict if they their holdShortcuts are included in the other's holdShortcuts
                    || (newCombo.1.keyCode == .none && oldCombo.1.keyCode == .none && (newCombo.1.modifierFlags.isSuperset(of: oldCombo.1.modifierFlags) || oldCombo.1.modifierFlags.isSuperset(of: newCombo.1.modifierFlags))) {
                    return oldCombo.0
                }
            }
        }
        return nil
    }

    /// commandTab and commandKeyAboveTab are self-contained in the "nextWindowShortcut" shortcuts
    /// but the keys of commandShiftTab can be spread between holdShortcut and a local shortcut
    static func combinedModifiersMatch(_ modifiers1: UInt32, _ modifiers2: UInt32) -> Bool {
        return (0..<Preferences.holdShortcut.count).contains {
            if let holdShortcut = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", $0)] {
                return (holdShortcut.shortcut.carbonModifierFlags | modifiers1) == (holdShortcut.shortcut.carbonModifierFlags | modifiers2)
            }
            return false
        }
    }
}

enum ShortcutAcceptance: Equatable {
    case accepted
    case modifiersOnlyButContainsKeycode
    case conflictWithExistingShortcut(shortcutAlreadyAssigned: String)
    case reservedByMacos(shortcutUsingEscape: String)

    static func == (lhs: ShortcutAcceptance, rhs: ShortcutAcceptance) -> Bool {
        switch (lhs, rhs) {
        case (.accepted, .accepted),
             (.modifiersOnlyButContainsKeycode, .modifiersOnlyButContainsKeycode),
             (.reservedByMacos, .reservedByMacos),
             (.conflictWithExistingShortcut, .conflictWithExistingShortcut):
            return true
        default:
            return false
        }
    }
}
/// Hard-set Force-Quit chords. macOS reserves these and they cannot be unbound, so AltTab refuses
/// to assign them. (`⌘⎋` was previously listed here for Game Overlay; it's been removed because
/// the cghid event tap in `KeyboardEvents` intercepts at HID level, before Game Overlay's hook —
/// see #5585.)
struct MacOsShortcuts {
    static let forceQuitApplicationsDialog = Shortcut(code: KeyCode.escape, modifierFlags: [.command, .option], characters: nil, charactersIgnoringModifiers: nil)
    static let forceQuitActiveApp = Shortcut(code: KeyCode.escape, modifierFlags: [.command, .option, .shift], characters: nil, charactersIgnoringModifiers: nil)
    static let reservedForUnknownReason = Shortcut(code: KeyCode.escape, modifierFlags: [.command, .option, .shift, .control], characters: nil, charactersIgnoringModifiers: nil)
}

enum ReservedMacosShortcut: CaseIterable {
    case forceQuitApplicationsDialog
    case forceQuitActiveApp
    case reservedForUnknownReason

    var basicShortcut: Shortcut {
        switch self {
        case .forceQuitApplicationsDialog: return MacOsShortcuts.forceQuitApplicationsDialog
        case .forceQuitActiveApp: return MacOsShortcuts.forceQuitActiveApp
        case .reservedForUnknownReason: return MacOsShortcuts.reservedForUnknownReason
        }
    }
}

extension Shortcut {
    /// Inverse of `Shortcut.init(keyEquivalent:)`: turns a `Shortcut` back into the same compact
    /// glyph form (e.g. `⌘⌥⇥`). ShortcutRecorder's built-in `readableStringRepresentation`
    /// returns the long form ("Command-Option-Tab"); this property rewrites that into the
    /// keyEquivalent glyphs.
    ///
    /// Used in production by `ControlsTab.shortcutSummary(_:)` to render the sidebar row's
    /// "summary" string ("⌘⌥ + ⇥"); also handy in tests for asserting against a recorded
    /// shortcut's glyph form.
    var keyEquivalent: String {
        get {
            let readableStringRepresentation = self.readableStringRepresentation(isASCII: true).lowercased()
            // for keycode-only shortcuts, readableStringRepresentation works
            if keyCode != .none && modifierFlags == [] && !readableStringRepresentation.isEmpty {
                return readableStringRepresentation
            }
            // for other shortcuts, we need to replace modifiers with unicode symbols (e.g. "Option-" -> "⌥")
            let flags: [(NSEvent.ModifierFlags, String)] = [
                (.command, "⌘"),
                (.option, "⌥"),
                (.control, "⌃"),
                (.shift, "⇧")
            ]
            let mods = flags.reduce("") {
                $0 + (self.modifierFlags.contains($1.0) ? $1.1 : "")
            }
            let chars = readableStringRepresentation.replacingOccurrences(of: "\\b(command|option|shift|control)-", with: "", options: .regularExpression)
            return mods + chars
        }
    }
}
