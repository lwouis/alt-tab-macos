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

    private enum ShortcutConflict {
        case arrow
        case vim
        case regular(control: CustomRecorderControl, label: String)
        case unknown

        var label: String {
            switch self {
            case .arrow: return "Arrow keys"
            case .vim: return "Vim keys"
            case .regular(_, let label): return label
            case .unknown: return "an unknown action"
            }
        }

        static func classify(_ id: String) -> ShortcutConflict {
            if ["←", "→", "↑", "↓"].contains(id) { return .arrow }
            if id.starts(with: "vimCycle") { return .vim }
            if let existing = ControlsTab.shortcutControls[id] {
                return .regular(control: existing.0, label: existing.1)
            }
            assertionFailure("conflict id '\(id)' missing from shortcutControls")
            return .unknown
        }
    }

    func alertIfSameShortcutAlreadyAssigned(_ candidateShortcut: Shortcut, _ shortcutAlreadyAssigned: String) {
        let conflict = ShortcutConflict.classify(shortcutAlreadyAssigned)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Shortcut already assigned to another action: %@", comment: ""),
                                       conflict.label.replacingOccurrences(of: " ", with: "\u{00A0}"))
        if !id.starts(with: "holdShortcut") {
            alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        }
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        if id.starts(with: "holdShortcut") {
            cancelButton.setAccessibilityFocused(true)
        }
        let userChoice = alert.runModal()
        guard !id.starts(with: "holdShortcut"), userChoice == .alertFirstButtonReturn else { return }
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
        case .regular(let existingControl, _):
            updateShortcut(existingControl, nil, existingControl, shortcutAlreadyAssigned)
        case .unknown:
            return
        }
        updateShortcut(self, candidateShortcut, self, id)
    }

    func updateShortcut(_ control: CustomRecorderControl, _ objectValue: Shortcut?, _ senderControl: NSControl, _ id: String) {
        control.objectValue = objectValue
        LabelAndControl.controlWasChanged(senderControl, id)
        ControlsTab.shortcutChangedCallback(senderControl)
    }

    func alertIfShortcutReservedByMacos(_ candidateShortcut: Shortcut, _ shortcutReservedByMacos: String) {
        let existing = ControlsTab.shortcutControls[shortcutReservedByMacos]
        if existing == nil {
            assertionFailure("reserved-by-macos id '\(shortcutReservedByMacos)' missing from shortcutControls")
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        alert.informativeText = String(format: NSLocalizedString("macOS reserves ⌘⌥⎋, ⌘⌥⇧⎋, and ⌘⌥⇧⌃⎋ for Force Quit and they cannot be unbound. AltTab cannot use them.\n\nYour change would assign one of these to: %@.", comment: ""), existing?.1 ?? "an unknown action")
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.setAccessibilityFocused(true)
        let userChoice = alert.runModal()
        guard userChoice == .alertFirstButtonReturn, id != shortcutReservedByMacos else { return }
        if let existing {
            updateShortcut(existing.0, nil, existing.0, shortcutReservedByMacos)
        }
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

