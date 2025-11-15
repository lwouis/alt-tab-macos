import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControl: RecorderControl {
    static let allowedModifiers = NSEvent.ModifierFlags(arrayLiteral: [.command, .control, .option, .shift])
    var clearable: Bool!
    var id: String!

    convenience init(_ shortcutString: String, _ clearable: Bool, _ id: String) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.clearable = clearable
        self.id = id
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsDeleteToClearShortcutAndEndRecording = false
        allowsModifierFlagsOnlyShortcut = true
        restrictModifiers([])
        objectValue = Shortcut(keyEquivalent: shortcutString)
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

    func alertIfSameShortcutAlreadyAssigned(_ candidateId: String, _ candidateShortcut: Shortcut, _ shortcutAlreadyAssigned: String) {
        let isArrowKeys = ["←", "→", "↑", "↓"].contains(shortcutAlreadyAssigned)
        let isVimKeys = shortcutAlreadyAssigned.starts(with: "vimCycle")
        let existingShortcut = ControlsTab.shortcutControls[shortcutAlreadyAssigned]!
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to another action: %@", comment: ""),
                                       (isArrowKeys ? "Arrow keys" : (isVimKeys ? "Vim keys" : existingShortcut.1)).replacingOccurrences(of: " ", with: "\u{00A0}"))
        if !candidateId.starts(with: "holdShortcut") {
            alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        }
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        if candidateId.starts(with: "holdShortcut") {
            cancelButton.setAccessibilityFocused(true)
        }
        let userChoice = alert.runModal()
        if !candidateId.starts(with: "holdShortcut") && userChoice == .alertFirstButtonReturn {
            if isArrowKeys {
                ControlsTab.arrowKeysCheckbox.state = .off
                ControlsTab.arrowKeysEnabledCallback(ControlsTab.arrowKeysCheckbox)
                LabelAndControl.controlWasChanged(ControlsTab.arrowKeysCheckbox, nil)
            } else if isVimKeys {
                ControlsTab.vimKeysCheckbox.state = .off
                ControlsTab.vimKeysEnabledCallback(ControlsTab.vimKeysCheckbox)
                LabelAndControl.controlWasChanged(ControlsTab.vimKeysCheckbox, nil)
            } else {
                existingShortcut.0.objectValue = nil
                ControlsTab.shortcutChangedCallback(existingShortcut.0)
                LabelAndControl.controlWasChanged(existingShortcut.0, shortcutAlreadyAssigned)
            }
            ControlsTab.shortcutControls[candidateId]!.0.objectValue = candidateShortcut
            ControlsTab.shortcutChangedCallback(self)
            LabelAndControl.controlWasChanged(self, candidateId)
        }
    }

    func alertIfShortcutReservedByMacos(_ candidateId: String, _ candidateShortcut: Shortcut, _ shortcutUsingEscape: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = NSLocalizedString("The ⎋ (escape) key is reserved by some macOS shortcuts (e.g. ⌘⌥⎋ will show the Force Quit Applications window).\n\nIf you want to use ⎋, make sure that Hold modifiers are neither: ⌘⌥, ⌘⌥⇧, or ⌘⌥⇧⌃", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityFocused(true)
        let userChoice = alert.runModal()
        if userChoice == .alertFirstButtonReturn {
            guard candidateId != shortcutUsingEscape else { return }
            let existingShortcut = ControlsTab.shortcutControls[shortcutUsingEscape]!
            existingShortcut.0.objectValue = nil
            ControlsTab.shortcutChangedCallback(existingShortcut.0)
            LabelAndControl.controlWasChanged(existingShortcut.0, shortcutUsingEscape)
            ControlsTab.shortcutControls[candidateId]!.0.objectValue = candidateShortcut
            ControlsTab.shortcutChangedCallback(self)
            LabelAndControl.controlWasChanged(self, candidateId)
        }
    }
}

extension CustomRecorderControl: RecorderControlDelegate {
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        switch CustomRecorderControlTestable.isShortcutAcceptable(id, shortcut) {
        case .accepted: return true
        case .modifiersOnlyButContainsKeycode: return false
        case .conflictWithExistingShortcut(let s): alertIfSameShortcutAlreadyAssigned(id, shortcut, s)
        case .reservedByMacos(let s): alertIfShortcutReservedByMacos(id, shortcut, s)
        }
        return true
    }
}


