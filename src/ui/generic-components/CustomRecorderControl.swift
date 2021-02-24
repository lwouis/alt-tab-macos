import Cocoa
import ShortcutRecorder

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
        set(allowedModifierFlags: CocoaModifierFlagsMask, requiredModifierFlags: [], allowsEmptyModifierFlags: true)
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

    // only allow modifiers: ⌥ -> valid, e -> invalid, ⌥e -> invalid
    func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
        if !clearable && shortcut.keyCode != .none {
            return false
        }
        alertIfSameShortcutAlreadyAssigned(shortcut)
        return true
    }

    func alertIfSameShortcutAlreadyAssigned(_ shortcut: Shortcut) {
        if let shortcutAlreadyAssigned = (ControlsTab.shortcuts.values.first {
            if $0.id == id || id.starts(with: "holdShortcut") || $0.id.starts(with: "holdShortcut") {
                return false
            }
            if $0.id.starts(with: "nextWindowShortcut") {
                return $0.shortcut.keyCode == shortcut.keyCode
            }
            return $0.shortcut.keyCode == shortcut.keyCode && $0.shortcut.modifierFlags == shortcut.modifierFlags
        }) {
            let existing = ControlsTab.shortcutControls[shortcutAlreadyAssigned.id]!
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
            alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to another action: %@", comment: ""), existing.1.replacingOccurrences(of: " ", with: "\u{00A0}"))
            alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
            let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
            cancelButton.keyEquivalent = "\u{1b}"
            let userChoice = alert.runModal()
            if userChoice == .alertFirstButtonReturn {
                existing.0.objectValue = nil
                ControlsTab.shortcutChangedCallback(existing.0)
                ControlsTab.shortcutControls[id]!.0.objectValue = shortcut
                ControlsTab.shortcutChangedCallback(self)
            }
        }
    }
}
