import Cocoa
import AppCenter
import AppCenterCrashes

class AppCenterCrash: NSObject {
    static let secret = Secrets.appCenterSecret

    override init() {
        super.init()
        // Enable catching uncaught exceptions thrown on the main thread
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
//        AppCenter.logLevel = .verbose
        // without this, appcenter makes network call just from AppCenter.start; we only want networking when sending reports
        AppCenter.networkRequestsAllowed = false
        // Wire the delegate + confirmation handler before start: AppCenter processes pending crash
        // reports synchronously inside +start, and if userConfirmationHandler is nil at that point
        // it falls through to MSACUserConfirmationSend and silently uploads without prompting.
        Crashes.delegate = self
        Crashes.userConfirmationHandler = confirmationHandler
        AppCenter.start(withAppSecret: AppCenterCrash.secret, services: [Crashes.self])
    }

    // at launch, the crash report handler can be called before some things are not yet ready; we ensure they are
    func initNecessaryFacilities() {
        if UserDefaults.standard.string(forKey: "crashPolicy") == nil {
            UserDefaults.standard.register(defaults: ["crashPolicy": "1"])
        }
    }

    // periphery:ignore
    func confirmationHandler(_ errorReports: [ErrorReport]) -> Bool {
        initNecessaryFacilities()
        // Defer the modal NSAlert to the next runloop tick. AppCenter can call this handler while
        // launch UI (QA Menu, Settings) is still being laid out by the WindowServer; running a
        // nested modal run loop on top of partially-displayed windows triggers
        // _NSDetectedLayoutRecursion when AppKit re-enters _setFrameCommon for those windows
        // (compounded by `App.shared.activate(ignoringOtherApps: true)` inside checkIfShouldSend,
        // which forces a global window resync). Returning `true` synchronously tells AppCenter the
        // user will be asked; the actual ask + Crashes.notify(with:) happen async.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let shouldSend = self.checkIfShouldSend()
            BackgroundWork.startCrashReportsQueue()
            BackgroundWork.crashReportsQueue.addOperation {
                // Don't toggle networkRequestsAllowed=false on the same tick: Crashes.notify only
                // enqueues the log into the channel DB; the channel flushes async over HTTP.
                // Re-disabling here pauses the channel before the POST goes out and the upload
                // never happens. The delegate callbacks below re-disable once the request finishes.
                AppCenter.networkRequestsAllowed = shouldSend
                Crashes.notify(with: shouldSend ? .send : .dontSend)
            }
        }
        return true
    }

    func checkIfShouldSend() -> Bool {
        if Preferences.crashPolicy == .ask {
            App.shared.activate(ignoringOtherApps: true)
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
            let id = crashButtonIdToUpdate(userChoice, checkbox)
            if let buttons = GeneralTab.crashPolicyDropdown, buttons.numberOfItems > id {
                buttons.selectItem(at: id)
            }
            Preferences.set("crashPolicy", String(id))
            return userChoice == .alertFirstButtonReturn
        }
        return Preferences.crashPolicy == .always
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
}

extension AppCenterCrash: CrashesDelegate {
    func attachments(with crashes: Crashes, for errorReport: ErrorReport) -> [ErrorAttachmentLog]? {
        // This delegate runs on `crashReportsQueue` (off-main; see `confirmationHandler`). `DebugProfile.make()`
        // must run on the main thread — it reads TIS/AppKit/model state (e.g. `Preferences.all` lazily inits
        // shortcut defaults via ShortcutRecorder → TIS, which SIGTRAPs off-main on macOS 26). This `.sync` can't
        // deadlock: the main thread never joins `crashReportsQueue`.
        let debugProfile = DispatchQueue.main.sync { DebugProfile.make() }
        return [ErrorAttachmentLog.attachment(withText: debugProfile, filename: "debug-profile.md")!]
    }

    func crashes(_ crashes: Crashes, didSucceedSending errorReport: ErrorReport) {
        AppCenter.networkRequestsAllowed = false
    }

    func crashes(_ crashes: Crashes, didFailSending errorReport: ErrorReport, withError error: Error?) {
        AppCenter.networkRequestsAllowed = false
    }
}
