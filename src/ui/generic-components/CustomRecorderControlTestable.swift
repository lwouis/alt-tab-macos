import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControlTestable {
    static func isShortcutAcceptable(_ candidateId: String, _ candidateShortcut: Shortcut) -> ShortcutAcceptance {
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
        if let shortcutUsingGameOverlay = isUsedByGameOverlay(newCombos) {
            return .usedByGameOverlay(shortcutUsingGameOverlay: shortcutUsingGameOverlay)
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
                // combine with local shortcut
                if (!atShortcut.id.starts(with: "holdShortcut") && !atShortcut.id.starts(with: "nextWindowShortcut"))
                    // combine with nextWindowShortcut of same index
                    || (atShortcut.id.starts(with: "nextWindowShortcut") && Preferences.nameToIndex(candidateId) == Preferences.nameToIndex(atShortcut.id)) {
                    combos.append((atShortcut.id, Shortcut(code: atShortcut.shortcut.keyCode, modifierFlags: [candidateShortcut.modifierFlags, atShortcut.shortcut.modifierFlags], characters: nil, charactersIgnoringModifiers: nil)))
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

    static func oldCombinationsExcludingTargetOfCandidate(_ candidateId: String) -> [(String, Shortcut)] {
        var holds = [ATShortcut]()
        var nonHolds = [ATShortcut]()
        for atShortcut in ControlsTab.shortcuts.values {
            guard !((candidateId.starts(with: "holdShortcut") || candidateId.starts(with: "nextWindowShortcut")) && (atShortcut.id.starts(with: "holdShortcut") || atShortcut.id.starts(with: "nextWindowShortcut")) && Preferences.nameToIndex(candidateId) == Preferences.nameToIndex(atShortcut.id) )
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

    static func isUsedByGameOverlay(_ newCombinationsFromCandidate: [(String, Shortcut)] ) -> String? {
        if #available(macOS 26.0, *) {
            let go = MacOsShortcuts.gameOverlay
            for c in newCombinationsFromCandidate {
                if c.1.carbonKeyCode == go.carbonKeyCode && c.1.carbonModifierFlags == go.carbonModifierFlags {
                    return c.0
                }
            }
        }
        return nil
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
    case usedByGameOverlay(shortcutUsingGameOverlay: String)

    static func == (lhs: ShortcutAcceptance, rhs: ShortcutAcceptance) -> Bool {
        switch (lhs, rhs) {
        case (.accepted, .accepted),
             (.modifiersOnlyButContainsKeycode, .modifiersOnlyButContainsKeycode),
             (.reservedByMacos, .reservedByMacos),
             (.usedByGameOverlay, .usedByGameOverlay),
             (.conflictWithExistingShortcut, .conflictWithExistingShortcut):
            return true
        default:
            return false
        }
    }
}
struct MacOsShortcuts {
    // Introduced in macOS 26. Can be toggled in System Settings
    static let gameOverlay = Shortcut(code: KeyCode.escape, modifierFlags: [.command], characters: nil, charactersIgnoringModifiers: nil)
    // Ancient shortcuts. Hard-set by the OS; can't be toggled by the user
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
    /// ShortcutRecorder doesn't provide a Shortcut.toString() that outputs the same format as Shortcut.init(keyEquivalent:)
    /// This helper provides this, on a limited range of shortcuts, since it used only for testing
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
