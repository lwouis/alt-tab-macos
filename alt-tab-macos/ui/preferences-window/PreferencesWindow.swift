import Cocoa
import Foundation

class PreferencesWindow: NSWindow, NSWindowDelegate {
    var windowCloseRequested = false
    let tabViewController = TabViewController()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, styleMask: style, backing: backingStoreType, defer: flag)
        LabelAndControl.callbackTarget = self
        setupWindow()
        setupTabViews()
    }

    func show() {
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func controlWasChanged(_ senderControl: NSControl) {
        let key: String = senderControl.identifier!.rawValue
        let previousValue: String = Preferences.rawValues[key]!
        let newValue: String = LabelAndControl.getControlValue(senderControl)
        let invalidTextField = senderControl is TextField && !(senderControl as! TextField).isValid()

        if (invalidTextField && !windowCloseRequested) || (newValue == previousValue && !invalidTextField) {
            return
        }

        LabelAndControl.updateControlExtras(senderControl, newValue)

        do {
            // TODO: remove conditional as soon a Preference does validation on its own
            if invalidTextField && windowCloseRequested {
                throw NSError.make(domain: "Preferences", message: "Please enter a valid value for '" + key + "'")
            }
            try Preferences.updateAndValidateFromString(key, newValue)
            (App.shared as! App).initPreferencesDependentComponents()
            try Preferences.saveRawToDisk()
        } catch let error {
            debugPrint("PreferencesWindow: save: error", key, newValue, error)
            showSaveErrorSheetModal(error as NSError, senderControl, key, previousValue) // allows recursive call by user choice
        }
    }

    private func setupWindow() {
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
    }

    private func setupTabViews() {
        contentViewController = tabViewController
        tabViewController.tabStyle = .toolbar
        tabViewController.addTabViewItem(ShortcutsTab.make())
        tabViewController.addTabViewItem(AppearanceTab.make())
        tabViewController.addTabViewItem(AboutTab.make())
    }

    private func challengeNextInvalidEditableTextField() {
        let invalidFields = (contentView?
                .findNestedViews(subclassOf: TextField.self)
                .filter({ !$0.isValid() })
        )
        let focusedField = invalidFields?.filter({ $0.currentEditor() != nil }).first
        let fieldToNotify = focusedField ?? invalidFields?.first
        fieldToNotify?.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: fieldToNotify))

        if fieldToNotify != focusedField {
            makeFirstResponder(fieldToNotify)
        }
    }

    private func showSaveErrorSheetModal(_ nsError: NSError, _ control: NSControl, _ key: String, _ previousValue: String) {
        let alert = NSAlert()
        alert.messageText = "Could not save Preference"
        alert.informativeText = nsError.localizedDescription + "\n"
        alert.addButton(withTitle: "Edit")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Check again")

        alert.beginSheetModal(for: self, completionHandler: { (modalResponse: NSApplication.ModalResponse) -> Void in
            if modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn {
                debugPrint("PreferencesWindow: save: error: user choice: edit")
                self.windowCloseRequested = false
            }
            if modalResponse == NSApplication.ModalResponse.alertSecondButtonReturn {
                debugPrint("PreferencesWindow: save: error: user choice: cancel -> revert value and eventually close window")
                try! Preferences.updateAndValidateFromString(key, previousValue)
                LabelAndControl.setControlValue(control, previousValue)
                LabelAndControl.updateControlExtras(control, previousValue)
                if self.windowCloseRequested {
                    self.close()
                }
            }
            if modalResponse == NSApplication.ModalResponse.alertThirdButtonReturn {
                debugPrint("PreferencesWindow: save: error: user choice: check again")
                self.controlWasChanged(control)
            }
        })
    }
}
