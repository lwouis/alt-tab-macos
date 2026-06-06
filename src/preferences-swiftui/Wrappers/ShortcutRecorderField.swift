import SwiftUI
import ShortcutRecorder
/// NSViewRepresentable wrapping `RecorderControl` for SwiftUI integration.
/// Handles shortcut recording and delegates value changes back to a SwiftUI `Binding`.
@available(macOS 13.0, *)
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var label: String = ""
    var allowedModifierFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    var restrictsToModifierOnly: Bool = false
    var preferenceKey: String?

    func makeNSView(context: Context) -> RecorderControl {
        let control = RecorderControl(frame: .zero)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.delegate = context.coordinator
        control.allowsEscapeToCancelRecording = false
        control.allowsDeleteToClearShortcutAndEndRecording = false
        control.allowsModifierFlagsOnlyShortcut = true
        control.set(
            allowedModifierFlags: allowedModifierFlags,
            requiredModifierFlags: [],
            allowsEmptyModifierFlags: true
        )
        control.objectValue = shortcut
        control.stringValue = label
        return control
    }

    func updateNSView(_ nsView: RecorderControl, context: Context) {
        context.coordinator.parent = self
        nsView.stringValue = label
        // Only update if shortcut changed externally to avoid recursion
        if nsView.objectValue != shortcut {
            nsView.objectValue = shortcut
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, RecorderControlDelegate {
        var parent: ShortcutRecorderField

        init(_ parent: ShortcutRecorderField) {
            self.parent = parent
        }

        func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
            guard let currentKey = parent.preferenceKey else {
                parent.shortcut = shortcut
                return true
            }
            // holdShortcut only allows modifier-only shortcuts
            if currentKey.starts(with: "holdShortcut") && shortcut.keyCode != .none {
                NSSound.beep()
                return false
            }
            // Combination-level conflict detection
            if isDuplicate(shortcut, currentKey: currentKey) {
                NSSound.beep()
                return false
            }
            parent.shortcut = shortcut
            return true
        }

        // MARK: - Combination-level conflict detection

        private static let activeKeys = [
            "focusWindowShortcut", "previousWindowShortcut", "cancelShortcut",
            "searchShortcut", "lockSearchShortcut", "closeWindowShortcut",
            "minDeminWindowShortcut", "toggleFullscreenWindowShortcut",
            "quitAppShortcut", "hideShowAppShortcut",
        ]

        /// All existing shortcut slot data.
        private struct SlotData {
            let holdKey: String
            let hold: Shortcut?
            let nextKey: String
            let next: Shortcut?
        }

        private func buildSlots() -> [SlotData] {
            let count = Preferences.shortcutCount
            return (0..<count).map { i in
                let hKey = Preferences.indexToName("holdShortcut", i)
                let nKey = Preferences.indexToName("nextWindowShortcut", i)
                return SlotData(
                    holdKey: hKey, hold: CachedUserDefaults.shortcut(hKey),
                    nextKey: nKey, next: CachedUserDefaults.shortcut(nKey)
                )
            }
        }

        private func makeCombo(keyCode: KeyCode, hold mods: NSEvent.ModifierFlags, key other: NSEvent.ModifierFlags) -> Shortcut {
            Shortcut(code: keyCode, modifierFlags: [mods, other], characters: nil, charactersIgnoringModifiers: nil)
        }

        private func hasContent(_ s: Shortcut?) -> Bool {
            guard let s = s else { return false }
            return s.keyCode != .none || !s.modifierFlags.isEmpty
        }

        /// Build all existing hold+nonHold combinations, excluding the candidate's own slot.
        private func buildExistingCombos(currentKey: String) -> [(String, Shortcut)] {
            let slots = buildSlots()
            var combos = [(String, Shortcut)]()
            for slot in slots {
                let isOwnSlot = currentKey == slot.holdKey || currentKey == slot.nextKey
                // hold × same-index nextWindow
                if !isOwnSlot, let h = slot.hold, let n = slot.next, hasContent(h), hasContent(n) {
                    combos.append((slot.nextKey, makeCombo(keyCode: n.keyCode, hold: h.modifierFlags, key: n.modifierFlags)))
                }
                // hold × Shortcuts When Active
                if let h = slot.hold, hasContent(h) {
                    for aKey in Self.activeKeys {
                        guard aKey != currentKey else { continue }
                        if let a = CachedUserDefaults.shortcut(aKey), hasContent(a) {
                            combos.append((aKey, makeCombo(keyCode: a.keyCode, hold: h.modifierFlags, key: a.modifierFlags)))
                        }
                    }
                }
            }
            return combos
        }

        /// Build all candidate combinations with existing shortcuts.
        private func buildCandidateCombos(_ candidate: Shortcut, currentKey: String) -> [(String, Shortcut)] {
            let slots = buildSlots()
            var combos = [(String, Shortcut)]()

            if currentKey.starts(with: "holdShortcut") {
                // hold × same-index nextWindow
                if let slot = slots.first(where: { $0.holdKey == currentKey }),
                   let n = slot.next, hasContent(n) {
                    combos.append((currentKey, makeCombo(keyCode: n.keyCode, hold: candidate.modifierFlags, key: n.modifierFlags)))
                }
                // hold × each Shortcuts When Active
                for aKey in Self.activeKeys {
                    if let a = CachedUserDefaults.shortcut(aKey), hasContent(a) {
                        combos.append((aKey, makeCombo(keyCode: a.keyCode, hold: candidate.modifierFlags, key: a.modifierFlags)))
                    }
                }
            } else if currentKey.starts(with: "nextWindowShortcut") {
                // nextWindow × same-index hold
                if let slot = slots.first(where: { $0.nextKey == currentKey }),
                   let h = slot.hold, hasContent(h) {
                    combos.append((currentKey, makeCombo(keyCode: candidate.keyCode, hold: h.modifierFlags, key: candidate.modifierFlags)))
                }
            } else {
                // Shortcuts When Active × each hold
                for slot in slots {
                    if let h = slot.hold, hasContent(h) {
                        combos.append((currentKey, makeCombo(keyCode: candidate.keyCode, hold: h.modifierFlags, key: candidate.modifierFlags)))
                    }
                }
            }
            return combos
        }

        private func isDuplicate(_ candidate: Shortcut, currentKey: String) -> Bool {
            let newCombos = buildCandidateCombos(candidate, currentKey: currentKey)
            let oldCombos = buildExistingCombos(currentKey: currentKey)
            for nc in newCombos {
                for oc in oldCombos {
                    guard nc.0 != oc.0 else { continue }
                    if nc.1.keyCode == oc.1.keyCode && nc.1.modifierFlags == oc.1.modifierFlags { return true }
                    if nc.1.keyCode == .none && oc.1.keyCode == .none
                        && (nc.1.modifierFlags.isSuperset(of: oc.1.modifierFlags) || oc.1.modifierFlags.isSuperset(of: nc.1.modifierFlags)) { return true }
                }
            }
            return false
        }
    }
}
