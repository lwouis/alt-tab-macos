import Cocoa
import ShortcutRecorder

class UnclearableRecorderControl: RecorderControl, RecorderControlDelegate {
    convenience init(_ shortcutString: String, _ modifierFlagsOnly: Bool) {
        self.init(frame: .zero)
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsDeleteToClearShortcutAndEndRecording = false
        set(allowedModifierFlags: CocoaModifierFlagsMask, requiredModifierFlags: [], allowsEmptyModifierFlags: true)
        if modifierFlagsOnly {
            allowsModifierFlagsOnlyShortcut = true
        }
        objectValue = Shortcut(keyEquivalent: shortcutString)
        widthAnchor.constraint(equalToConstant: 100).isActive = true
    }

    override func drawClearButton(_ aDirtyRect: NSRect) {
        if !allowsModifierFlagsOnlyShortcut {
            super.drawClearButton(aDirtyRect)
        }
    }

    func recorderControl(_ aControl: RecorderControl, canRecord aShortcut: Shortcut) -> Bool {
        // only allow modifiers: ⌥ -> valid, e -> invalid, ⌥e -> invalid
        if allowsModifierFlagsOnlyShortcut && aShortcut.keyCode != .none {
            return false
        }
        return true
    }
}
