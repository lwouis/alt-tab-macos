import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControl: RecorderControl {
    static let allowedModifiers = NSEvent.ModifierFlags(arrayLiteral: [.command, .control, .option, .shift])
    var clearable: Bool!
    /// The preference key this recorder edits. Derived from `identifier` (set in `init` and re-aimed
    /// by `TriggerBinding.bind` as the recycled editor switches shortcuts) so it can never drift out
    /// of sync with the key the write path (`controlWasChanged`) and the conflict detector key off.
    var id: String { identifier!.rawValue }

    convenience init(_ shortcutString: String, _ clearable: Bool, _ id: String) {
        self.init(Shortcut(keyEquivalent: shortcutString), clearable, id)
    }

    convenience init(_ shortcut: Shortcut?, _ clearable: Bool, _ id: String) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.clearable = clearable
        identifier = NSUserInterfaceItemIdentifier(id)
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsDeleteToClearShortcutAndEndRecording = false
        allowsModifierFlagsOnlyShortcut = true
        restrictModifiers([])
        objectValue = shortcut
        addOrUpdateConstraint(widthAnchor, 100)
    }

    override func drawClearButton(_ aDirtyRect: NSRect) {
        if clearable {
            super.drawClearButton(aDirtyRect)
        }
    }

    override func clearAndEndRecording() {
        if clearable {
            super.clearAndEndRecording()
        }
    }

    func restrictModifiers(_ restrictedModifiers: NSEvent.ModifierFlags) {
        set(allowedModifierFlags: CustomRecorderControl.allowedModifiers.subtracting(restrictedModifiers), requiredModifierFlags: [], allowsEmptyModifierFlags: true)
    }

    /// How to clear the conflicting shortcut when the user picks "Unassign and continue". Resolved
    /// from the id alone — arrow/vim are toggled off via their checkboxes; everything else is cleared
    /// through `Preferences` by id (so a shortcut that isn't on screen is handled correctly). The
    /// human-readable label shown in the dialog comes separately from `ControlsTab.conflictLabel`.
    private enum ShortcutConflict {
        case arrow
        case vim
        case regular(id: String)

        static func classify(_ id: String) -> ShortcutConflict {
            if ["←", "→", "↑", "↓"].contains(id) { return .arrow }
            if id.starts(with: "vimCycle") { return .vim }
            return .regular(id: id)
        }
    }

    func alertIfSameShortcutAlreadyAssigned(_ candidateShortcut: Shortcut, _ shortcutAlreadyAssigned: String) {
        let conflict = ShortcutConflict.classify(shortcutAlreadyAssigned)
        // `conflictLabel` returns nil only for an id with no known action, which can't happen for a
        // real detected conflict; keep the prior plain-string fallback (not a new l10n key).
        let label = ControlsTab.conflictLabel(shortcutAlreadyAssigned) ?? "an unknown action"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to: %@", comment: ""),
                                       label.replacingOccurrences(of: " ", with: "\u{00A0}"))
        // Always offer to resolve it, including when editing a Hold: unassigning a conflicting Trigger
        // clears its "and press" part (the hold itself is never the thing unassigned).
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        let userChoice = alert.runModal()
        guard userChoice == .alertFirstButtonReturn else { return }
        switch conflict {
        case .arrow:
            if let cb = ControlsTab.arrowKeysCheckbox {
                cb.state = .off
                ControlsTab.arrowKeysEnabledCallback(cb)
                LabelAndControl.controlWasChanged(cb, nil)
            }
        case .vim:
            if let cb = ControlsTab.vimKeysCheckbox {
                cb.state = .off
                ControlsTab.vimKeysEnabledCallback(cb)
                LabelAndControl.controlWasChanged(cb, nil)
            }
        case .regular(let conflictingId):
            ControlsTab.unassignShortcut(conflictingId)
        }
        updateShortcut(self, candidateShortcut, self, id)
    }

    func updateShortcut(_ control: CustomRecorderControl, _ objectValue: Shortcut?, _ senderControl: NSControl, _ id: String) {
        control.objectValue = objectValue
        LabelAndControl.controlWasChanged(senderControl, id)
        ControlsTab.shortcutChangedCallback(senderControl)
    }

    func alertIfShortcutReservedByMacos(_ candidateShortcut: Shortcut, _ shortcutReservedByMacos: String) {
        let label = ControlsTab.conflictLabel(shortcutReservedByMacos) ?? "an unknown action"
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("macOS reserves ⌘⌥⎋, ⌘⌥⇧⎋, and ⌘⌥⇧⌃⎋ for Force Quit and they cannot be unbound. AltTab cannot use them.\n\nYour change would assign one of these to: %@.", comment: ""), label)
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityFocused(true)
        let userChoice = alert.runModal()
        guard userChoice == .alertFirstButtonReturn, id != shortcutReservedByMacos else { return }
        ControlsTab.unassignShortcut(shortcutReservedByMacos)
        updateShortcut(self, candidateShortcut, self, id)
    }

    func save(_ candidateShortcut: Shortcut) {
        LabelAndControl.controlWasChanged(self, id)
        // shortcutChangedCallback is called automatically here
        // setting objectValue also happens automatically
    }
}

extension CustomRecorderControl: RecorderControlDelegate {
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        switch CustomRecorderControlTestable.isShortcutAcceptable(id, shortcut) {
        case .accepted: save(shortcut)
        case .modifiersOnlyButContainsKeycode: return false
        case .conflictWithExistingShortcut(let s): alertIfSameShortcutAlreadyAssigned(shortcut, s)
        case .reservedByMacos(let s): alertIfShortcutReservedByMacos(shortcut, s)
        }
        return true
    }
}

