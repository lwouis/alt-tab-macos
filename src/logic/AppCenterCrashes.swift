import Cocoa
import AppCenter
import AppCenterCrashes

class AppCenterCrash: NSObject, MSCrashesDelegate {
    static let secret = Bundle.main.object(forInfoDictionaryKey: "AppCenterSecret") as! String

    override init() {
        super.init()
        // Enable catching uncaught exceptions thrown on the main thread
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
//        MSAppCenter.setLogLevel(MSLogLevel.none)
        MSAppCenter.start(AppCenterCrash.secret, withServices: [MSCrashes.self])
        MSCrashes.setDelegate(self)
        // when the app starts, this code can execute before defaults are set; we pre-set this default in case
        defaults.register(defaults: ["crashPolicy": "1"])
        MSCrashes.setUserConfirmationHandler({ (errorReports: [MSErrorReport]) in
            if Preferences.crashPolicy == .ask {
                App.app.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = NSLocalizedString("Send a crash report?", comment: "")
                alert.informativeText = NSLocalizedString("AltTab crashed last time you used it. Sending a crash report will help get the issue fixed", comment: "")
                alert.addButton(withTitle: NSLocalizedString("Send", comment: "")).setAccessibilityFocused(true)
                let cancelButton = alert.addButton(withTitle: NSLocalizedString("Don’t send", comment: ""))
                cancelButton.keyEquivalent = "\u{1b}"
                let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("Remember my choice", comment: ""), target: nil, action: nil)
                alert.accessoryView = checkbox
                let userChoice = alert.runModal()
                let id = self.crashButtonIdToUpdate(userChoice, checkbox)
                PoliciesTab.crashButtons[id].state = .on
                Preferences.set("crashPolicy", String(id))
                BackgroundWork.crashReportsQueue.async { MSCrashes.notify(with: userChoice == .alertFirstButtonReturn ? .send : .dontSend) }
            } else {
                BackgroundWork.crashReportsQueue.async { MSCrashes.notify(with: Preferences.crashPolicy == .always ? .send : .dontSend) }
            }
            return true
        })
    }

    func crashButtonIdToUpdate(_ userChoice: NSApplication.ModalResponse, _ checkbox: NSButton) -> Int {
        if userChoice == .alertFirstButtonReturn {
            if checkbox.state == .on {
                return 2
            }
            return 1
        }
        if checkbox.state == .on {
            return 0
        }
        return 1
    }

    func attachments(with crashes: MSCrashes, for errorReport: MSErrorReport) -> [MSErrorAttachmentLog] {
        return [MSErrorAttachmentLog.attachment(withText: DebugProfile.make(), filename: "debug-profile.md")!]
    }
}
