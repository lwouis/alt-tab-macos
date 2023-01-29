import Cocoa
import ShortcutRecorder

let allowedModifiers = NSEvent.ModifierFlags(arrayLiteral: [.command, .control, .option, .shift])

class CustomRecorderControl: RecorderControl, RecorderControlDelegate {
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
        widthAnchor.constraint(equalToConstant: 100).isActive = true
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
        set(allowedModifierFlags: allowedModifiers.subtracting(restrictedModifiers), requiredModifierFlags: [], allowsEmptyModifierFlags: true)
    }

    /// only allow modifiers: ⌥ -> valid, e -> invalid, ⌥e -> invalid
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        if !clearable && shortcut.keyCode != .none {
            return false
        }
        if let shortcutAlreadyAssigned = isShortcutAlreadyAssigned(shortcut) {
            alertIfSameShortcutAlreadyAssigned(shortcut, shortcutAlreadyAssigned)
        }
        return true
    }

    func alertIfSameShortcutAlreadyAssigned(_ shortcut: Shortcut, _ shortcutAlreadyAssigned: ATShortcut) {
        let isArrowKeys = ["←", "→", "↑", "↓"].contains(shortcutAlreadyAssigned.id)
        let existing = ControlsTab.shortcutControls[shortcutAlreadyAssigned.id]
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to another action: %@", comment: ""), (isArrowKeys ? "Arrow keys" : existing!.1).replacingOccurrences(of: " ", with: "\u{00A0}"))
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
            if isArrowKeys {
                ControlsTab.arrowKeysCheckbox.state = .off
                ControlsTab.arrowKeysEnabledCallback(ControlsTab.arrowKeysCheckbox)
                LabelAndControl.controlWasChanged(ControlsTab.arrowKeysCheckbox, nil)
            } else {
                existing!.0.objectValue = nil
                ControlsTab.shortcutChangedCallback(existing!.0)
                LabelAndControl.controlWasChanged(existing!.0, shortcutAlreadyAssigned.id)
            }
            ControlsTab.shortcutControls[id]!.0.objectValue = shortcut
            ControlsTab.shortcutChangedCallback(self)
            LabelAndControl.controlWasChanged(self, id)
        }
    }

    private func isShortcutAlreadyAssigned(_ shortcut: Shortcut) -> ATShortcut? {
        let comboShortcutName = id.starts(with: "holdShortcut") ?
            Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(id)) :
            (id.starts(with: "nextWindowShortcut") ?
                Preferences.indexToName("holdShortcut", Preferences.nameToIndex(id)) : id)
        let comboShortcut = comboShortcutName.flatMap { ControlsTab.shortcuts[$0]?.shortcut }
        return (ControlsTab.shortcuts.first { (id2, s2) in
            let shortcut2 = s2.shortcut
            if id == id2
                   || (shortcut2.keyCode == .none && shortcut2.carbonModifierFlags == 0)
                   || id2.starts(with: "holdShortcut")
                   || ((id.starts(with: "holdShortcut") || id.starts(with: "nextWindowShortcut")) && id2 == comboShortcutName) {
                return false
            }
            if comboShortcutName?.starts(with: "holdShortcut") ?? false {
                // you can have command tab open and close the flow for example
                return false
            }
            if shortcut2.keyCode != (id.starts(with: "holdShortcut") ? comboShortcut?.keyCode : shortcut.keyCode) {
                return false
            }
            if id.starts(with: "holdShortcut") {
                if ((comboShortcut?.carbonModifierFlags ?? 0) ^ (ControlsTab.shortcuts[id]?.shortcut.carbonModifierFlags ?? 0) | shortcut.carbonModifierFlags)
                       != (shortcut.carbonModifierFlags | shortcut2.carbonModifierFlags) {
                    return false
                }
            } else if id.starts(with: "nextWindowShortcut") {
                if ((comboShortcut?.carbonModifierFlags ?? 0) | shortcut.carbonModifierFlags)
                       != ((comboShortcut?.carbonModifierFlags ?? 0) | shortcut2.carbonModifierFlags) {
                    return false
                }
            } else if !ControlsTab.combinedModifiersMatch(shortcut2.carbonModifierFlags, shortcut.carbonModifierFlags) {
                return false
            }
            return true
        })?.value
    }
}
