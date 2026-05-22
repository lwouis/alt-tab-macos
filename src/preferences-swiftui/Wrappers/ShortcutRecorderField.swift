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
        let parent: ShortcutRecorderField

        init(_ parent: ShortcutRecorderField) {
            self.parent = parent
        }

        func recorderControl(_ control: RecorderControl, canRecord shortcut: Shortcut) -> Bool {
            parent.shortcut = shortcut
            return true
        }
    }
}
