import Cocoa
import ShortcutRecorder

class UnclearableRecorderControl: RecorderControl {
    convenience init(_ shortcutString: String, _ modifierFlagsOnly: Bool) {
        self.init(frame: .zero)
        allowsDeleteToClearShortcutAndEndRecording = false
        set(allowedModifierFlags: CocoaModifierFlagsMask, requiredModifierFlags: [], allowsEmptyModifierFlags: false)
        if modifierFlagsOnly {
            allowsModifierFlagsOnlyShortcut = true
        }
        objectValue = Shortcut(keyEquivalent: shortcutString)
        // TODO: doesn't seem to work; handle width of the control better
        allowsExpansionToolTips = true
        widthAnchor.constraint(equalToConstant: 80).isActive = true
    }

    override func drawClearButton(_ aDirtyRect: NSRect) {
        // don't draw the clear button
    }

    override func areModifierFlagsValid(_ aModifierFlags: NSEvent.ModifierFlags, for aKeyCode: KeyCode) -> Bool {
        // only allow modifiers: ⌥ -> valid, e -> invalid, ⌥e -> invalid
        if allowsModifierFlagsOnlyShortcut && aKeyCode != .none {
            return false
        }
        return super.areModifierFlagsValid(aModifierFlags, for: aKeyCode)
    }
}
