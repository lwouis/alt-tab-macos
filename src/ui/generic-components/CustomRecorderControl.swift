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

    // only allow modifiers: ⌥ -> valid, e -> invalid, ⌥e -> invalid
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
        ControlsTab.shortcuts.values.first {
            if id == $0.id {
                return false
            }
            if (id.starts(with: "holdShortcut") && $0.id.starts(with: "holdShortcut") || (id.starts(with: "nextWindowShortcut")) && $0.id.starts(with: "nextWindowShortcut")) {
                let index = Preferences.nameToIndex(id)
                let otherIndex = Preferences.nameToIndex($0.id)
                if id.starts(with: "holdShortcut") {
                    return Preferences.nextWindowShortcut[index] == Preferences.nextWindowShortcut[otherIndex] &&
                        shortcut.modifierFlags == ControlsTab.shortcutControls[Preferences.indexToName("holdShortcut", otherIndex)]!.0.objectValue!.modifierFlags
                }
                if id.starts(with: "nextWindowShortcut") {
                    if let nextWindowShortcut = ControlsTab.shortcutControls[Preferences.indexToName("nextWindowShortcut", otherIndex)]?.0.objectValue {
                        return Preferences.holdShortcut[index] == Preferences.holdShortcut[otherIndex] &&
                            shortcut.modifierFlags == nextWindowShortcut.modifierFlags &&
                            shortcut.keyCode == nextWindowShortcut.keyCode
                    }
                    return false
                }
            }
            if $0.id.starts(with: "nextWindowShortcut") {
                let index = Preferences.nameToIndex($0.id)
                return $0.shortcut.keyCode == shortcut.keyCode && ($0.shortcut.carbonModifierFlags ^ ControlsTab.shortcutControls[Preferences.indexToName("holdShortcut", index)]!.0.objectValue!.carbonModifierFlags) == shortcut.carbonModifierFlags
            }
            return $0.shortcut.keyCode == shortcut.keyCode && $0.shortcut.modifierFlags == shortcut.modifierFlags
        }
    }
}
