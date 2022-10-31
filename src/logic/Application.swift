import Cocoa
import ApplicationServices.HIServices.AXNotificationConstants

class Application: NSObject {
    // kvObservers should be listed first, so it gets deinit'ed first; otherwise it can crash
    var kvObservers: [NSKeyValueObservation]?
    var runningApplication: NSRunningApplication
    var axUiElement: AXUIElement?
    var axObserver: AXObserver?
    var isReallyFinishedLaunching = false
    var isHidden: Bool!
    var hasBeenActiveOnce: Bool!
    var icon: NSImage?
    var dockLabel: String?
    var pid: pid_t!
    var focusedWindow: Window? = nil
    var alreadyRequestedToQuit = false

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        pid = runningApplication.processIdentifier
        super.init()
        isHidden = runningApplication.isHidden
        hasBeenActiveOnce = runningApplication.isActive
        icon = runningApplication.icon
        observeEventsIfEligible()
        kvObservers = [
            runningApplication.observe(\.isFinishedLaunching, options: [.new]) { [weak self] _, _ in
                guard let self = self else { return }
                self.observeEventsIfEligible()
            },
            runningApplication.observe(\.activationPolicy, options: [.new]) { [weak self] _, _ in
                guard let self = self else { return }
                if self.runningApplication.activationPolicy != .regular {
                    self.removeWindowslessAppWindow()
                }
                self.observeEventsIfEligible()
            },
        ]
    }

    deinit {
        debugPrint("Deinit app", runningApplication.bundleIdentifier ?? runningApplication.bundleURL ?? "nil")
    }

    func removeWindowslessAppWindow() {
        if let windowlessAppWindow = (Windows.list.firstIndex { $0.isWindowlessApp == true && $0.application.pid == pid }) {
            Windows.list.remove(at: windowlessAppWindow)
            App.app.refreshOpenUi()
        }
    }

    func observeEventsIfEligible() {
        if runningApplication.activationPolicy != .prohibited && axUiElement == nil {
            axUiElement = AXUIElementCreateApplication(pid)
            AXObserverCreate(pid, axObserverCallback, &axObserver)
            debugPrint("Adding app", pid ?? "nil", runningApplication.bundleIdentifier ?? "nil")
            observeEvents()
        }
    }

    func manuallyUpdateWindows(_ group: DispatchGroup? = nil) {
        // TODO: this method manually checks windows, but will not find windows on other Spaces
        retryAxCallUntilTimeout(group, 5) { [weak self] in
            guard let self = self else { return }
            if let axWindows_ = try self.axUiElement!.windows(), axWindows_.count > 0 {
                // bug in macOS: sometimes the OS returns multiple duplicate windows (e.g. Mail.app starting at login)
                try Array(Set(axWindows_)).forEach { axWindow in
                    if let wid = try axWindow.cgWindowId() {
                        let title = try axWindow.title()
                        let subrole = try axWindow.subrole()
                        let role = try axWindow.role()
                        let size = try axWindow.size()
                        let level = try wid.level()
                        if AXUIElement.isActualWindow(self.runningApplication, wid, level, title, subrole, role, size) {
                            let isFullscreen = try axWindow.isFullscreen()
                            let isMinimized = try axWindow.isMinimized()
                            let position = try axWindow.position()
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                if let window = self.addWindow(axWindow, wid, title, isFullscreen, isMinimized, position, size) {
                                    App.app.refreshOpenUi([window])
                                } else if let window = self.addWindowslessAppsIfNeeded() {
                                    App.app.refreshOpenUi(window)
                                }
                            }
                        }
                    }
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let window = self.addWindowslessAppsIfNeeded()
                    App.app.refreshOpenUi(window)
                }
                // workaround: some apps launch but take a while to create their window(s)
                // initial windows don't trigger a windowCreated notification, so we won't get notified
                // it's very unlikely an app would launch with no initial window
                // so we retry until timeout, in those rare cases (e.g. Bear.app)
                // we only do this for active app, to avoid wasting CPU, with the trade-off of maybe missing some windows
                if self.runningApplication.isActive {
                    throw AxError.runtimeError
                }
            }
        }
    }

    func addWindowslessAppsIfNeeded() -> [Window]? {
        if !Preferences.hideWindowlessApps &&
               runningApplication.activationPolicy == .regular &&
               !runningApplication.isTerminated &&
               (Windows.list.firstIndex { $0.application.pid == pid }) == nil {
            let window = Window(self)
            Windows.appendAndUpdateFocus(window)
            return [window]
        }
        return nil
    }

    func hideOrShow() {
        if runningApplication.isHidden {
            runningApplication.unhide()
        } else {
            runningApplication.hide()
        }
    }

    func canBeQuit() -> Bool {
        return runningApplication.bundleIdentifier != "com.apple.finder" || Preferences.finderShowsQuitMenuItem
    }

    func quit() {
        // only let power users quit Finder if they opt-in
        if !canBeQuit() {
            NSSound.beep()
            return
        }
        if alreadyRequestedToQuit {
            runningApplication.forceTerminate()
        } else {
            runningApplication.terminate()
            alreadyRequestedToQuit = true
        }
    }

    private func addWindow(_ axUiElement: AXUIElement, _ wid: CGWindowID, _ axTitle: String?, _ isFullscreen: Bool, _ isMinimized: Bool, _ position: CGPoint?, _ size: CGSize?) -> Window? {
        if (Windows.list.firstIndex { $0.isEqualRobust(axUiElement, wid) }) == nil {
            let window = Window(axUiElement, self, wid, axTitle, isFullscreen, isMinimized, position, size)
            Windows.appendAndUpdateFocus(window)
            if App.app.appIsBeingUsed {
                Windows.cycleFocusedWindowIndex(1)
            }
            return window
        }
        return nil
    }

    private func observeEvents() {
        guard let axObserver = axObserver else { return }
        for notification in [
            kAXApplicationActivatedNotification,
            kAXMainWindowChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXApplicationHiddenNotification,
            kAXApplicationShownNotification,
        ] {
            retryAxCallUntilTimeout { [weak self] in
                guard let self = self else { return }
                try self.axUiElement!.subscribeToNotification(axObserver, notification, {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // some apps have `isFinishedLaunching == true` but are actually not finished, and will return .cannotComplete
                        // we consider them ready when the first subscription succeeds
                        // windows opened before that point won't send a notification, so check those windows manually here
                        if !self.isReallyFinishedLaunching {
                            self.isReallyFinishedLaunching = true
                            self.manuallyUpdateWindows()
                        }
                    }
                }, self.runningApplication)
            }
        }
        CFRunLoopAddSource(BackgroundWork.accessibilityEventsThread.runLoop, AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
}
