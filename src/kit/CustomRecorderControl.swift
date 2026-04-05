import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class CustomRecorderControl: RecorderControl {
    static let allowedModifiers = NSEvent.ModifierFlags(arrayLiteral: [.command, .control, .option, .shift])
    var clearable: Bool!
    var id: String!

    convenience init(_ shortcutString: String, _ clearable: Bool, _ id: String) {
        self.init(Shortcut(keyEquivalent: shortcutString), clearable, id)
    }

    convenience init(_ shortcut: Shortcut?, _ clearable: Bool, _ id: String) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.clearable = clearable
        self.id = id
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

    func alertIfSameShortcutAlreadyAssigned(_ candidateShortcut: Shortcut, _ shortcutAlreadyAssigned: String) {
        let isArrowKeys = ["←", "→", "↑", "↓"].contains(shortcutAlreadyAssigned)
        let isVimKeys = shortcutAlreadyAssigned.starts(with: "vimCycle")
        let existingShortcut = ControlsTab.shortcutControls[shortcutAlreadyAssigned]!
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to another action: %@", comment: ""),
                                       (isArrowKeys ? "Arrow keys" : (isVimKeys ? "Vim keys" : existingShortcut.1)).replacingOccurrences(of: " ", with: "\u{00A0}"))
        if !id.starts(with: "holdShortcut") {
            alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        }
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        if id.starts(with: "holdShortcut") {
            cancelButton.setAccessibilityFocused(true)
        }
        let userChoice = alert.runModal()
        if !id.starts(with: "holdShortcut") && userChoice == .alertFirstButtonReturn {
            if isArrowKeys, let cb = ControlsTab.arrowKeysCheckbox {
                cb.state = .off
                ControlsTab.arrowKeysEnabledCallback(cb)
                LabelAndControl.controlWasChanged(cb, nil)
            } else if isVimKeys, let cb = ControlsTab.vimKeysCheckbox {
                cb.state = .off
                ControlsTab.vimKeysEnabledCallback(cb)
                LabelAndControl.controlWasChanged(cb, nil)
            } else {
                updateShortcut(existingShortcut.0, nil, existingShortcut.0, shortcutAlreadyAssigned)
            }
            if let target = ControlsTab.shortcutControls[id]?.0 {
                updateShortcut(target, candidateShortcut, self, id)
            }
        }
    }

    func updateShortcut(_ control: CustomRecorderControl, _ objectValue: Shortcut?, _ senderControl: NSControl, _ id: String) {
        control.objectValue = objectValue
        LabelAndControl.controlWasChanged(senderControl, id)
        ControlsTab.shortcutChangedCallback(senderControl)
    }

    func alertIfShortcutReservedByMacos(_ candidateShortcut: Shortcut, _ shortcutReservedByMacos: String) {
        let existingShortcutLabel = ControlsTab.shortcutControls[shortcutReservedByMacos]!.1
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("macOS reserves ⌘⌥⎋, ⌘⌥⇧⎋, and ⌘⌥⇧⌃⎋ for Force Quit and they cannot be unbound. AltTab cannot use them.\n\nYour change would assign one of these to: %@.", comment: ""), existingShortcutLabel)
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityFocused(true)
        let userChoice = alert.runModal()
        if userChoice == .alertFirstButtonReturn {
            guard id != shortcutReservedByMacos else { return }
            let existingShortcut = ControlsTab.shortcutControls[shortcutReservedByMacos]!
            updateShortcut(existingShortcut.0, nil, existingShortcut.0, shortcutReservedByMacos)
            updateShortcut(ControlsTab.shortcutControls[id]!.0, candidateShortcut, self, id)
        }
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

