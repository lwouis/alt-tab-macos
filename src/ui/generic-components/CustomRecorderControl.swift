import Cocoa
import ShortcutRecorder

class CustomRecorderControl: RecorderControl, RecorderControlDelegate {
    var clearable: Bool!

    convenience init(_ shortcutString: String, _ clearable: Bool) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.clearable = clearable
        delegate = self
        allowsEscapeToCancelRecording = false
        allowsDeleteToClearShortcutAndEndRecording = false
        allowsModifierFlagsOnlyShortcut = true
        set(
            allowedModifierFlags: CocoaModifierFlagsMask, requiredModifierFlags: [],
            allowsEmptyModifierFlags: true)
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
    func recorderControl(_ aControl: RecorderControl, canRecord aShortcut: Shortcut) -> Bool {
        if !clearable && aShortcut.keyCode != .none {
            return false
        }
        return true
    }
}
