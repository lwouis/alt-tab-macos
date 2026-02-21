import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXNotificationConstants

class AccessibilityEvents {
    static let axObserverCallback: AXObserverCallback = { _, element, notificationName, _ in
        let type = notificationName as String
        Logger.debug { type }
        AXUIElement.retryAxCallUntilTimeout(context: "(type:\(type)", callType: .axEventEntrypoint) {
            try handleEvent(type, element)
        }
    }

    private static func handleEvent(_ type: String, _ element: AXUIElement) throws {
        let pid = try element.pid()
        Logger.debug { "\(type) pid:\(pid)" }
        if [kAXApplicationActivatedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification].contains(type) {
            AXUIElement.retryAxCallUntilTimeout(context: "(pid:\(pid))", pid: pid, callType: .updateApp) {
                try handleEventApp(type, pid, element)
            }
        } else {
            let wid = (try? element.cgWindowId()) ?? 0
            AXUIElement.retryAxCallUntilTimeout(context: "(pid:\(pid))", pid: pid, wid: wid, isWindowDestroyedEvent: type == kAXUIElementDestroyedNotification, callType: .updateWindowFromAxEvent) {
                try handleEventWindow(type, wid, pid, element)
            }
        }
    }

    private static func handleEventApp(_ type: String, _ pid: pid_t, _ element: AXUIElement) throws {
        let appFocusedWindow = try element.attributes([kAXFocusedWindowAttribute]).focusedWindow
        let wid = try appFocusedWindow?.cgWindowId()
        DispatchQueue.main.async {
            guard let app = Applications.findOrCreate(pid, false) else { return }
            Logger.info { "\(type) app:\(app.debugId)" }
            if type == kAXApplicationActivatedNotification {
                applicationActivated(app, pid, type, appFocusedWindow, wid)
            } else if type == kAXApplicationHiddenNotification || type == kAXApplicationShownNotification {
                applicationHiddenOrShown(app, pid, type)
            }
        }
    }

    private static func applicationActivated(_ app: Application, _ pid: pid_t, _ type: String, _ appFocusedWindow: AXUIElement?, _ wid: CGWindowID?) {
        Applications.frontmostPid = pid
        if app.hasBeenActiveOnce != true {
            app.hasBeenActiveOnce = true
        }
        if let appFocusedWindow, let wid {
            // if there is a focusedWindow, we reuse existing code to process it as if it was a kAXFocusedWindowChangedNotification
            AXUIElement.retryAxCallUntilTimeout(context: "\(type) \(app.debugId))", pid: pid, wid: wid, callType: .updateWindowFromAxEvent) {
                try handleEventWindow(kAXFocusedWindowChangedNotification, wid, pid, appFocusedWindow)
            }
        } else {
            App.checkIfShortcutsShouldBeDisabled(nil, app)
            if let windowless = (Windows.list.first { $0.isWindowlessApp && $0.application.pid == pid }) {
                if let windows = Windows.updateLastFocusOrder(windowless) {
                    App.refreshOpenUiAfterExternalEvent(windows)
                }
            }
        }
    }

    private static func applicationHiddenOrShown(_ app: Application, _ pid: pid_t, _ type: String) {
        app.isHidden = type == kAXApplicationHiddenNotification
        let windows = Windows.list.filter {
            // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
            return $0.application.pid == pid
        }
        // if we process the "shown" event too fast, the window won't be listed by CGSCopyWindowsWithOptionsAndTags
        // it will thus be detected as isTabbed. We add a delay to work around this scenario
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            App.refreshOpenUiAfterExternalEvent(windows)
        }
    }

    static func handleEventWindow(_ type: String, _ wid: CGWindowID, _ pid: pid_t, _ element: AXUIElement) throws {
        guard wid != 0 || type == kAXUIElementDestroyedNotification,
              wid != TilesPanel.shared.windowNumber else { return } // don't process events for the thumbnails panel
        if type == kAXUIElementDestroyedNotification {
            DispatchQueue.main.async {
                Logger.info { "\(type) wid:\(wid) pid:\(pid)" }
                windowDestroyed(element, pid, wid)
            }
            return
        }
        let level = wid.level()
        let a = try element.attributes([kAXTitleAttribute, kAXSubroleAttribute, kAXRoleAttribute, kAXSizeAttribute, kAXPositionAttribute, kAXFullscreenAttribute, kAXMinimizedAttribute])
        DispatchQueue.main.async {
            guard let app = Applications.findOrCreate(pid, false) else { return }
            Logger.info { "\(type) wid:\(wid) app:\(app.debugId)" }
            let findOrCreate = Windows.findOrCreate(element, wid, app, level, a.title, a.subrole, a.role, a.size, a.position, a.isFullscreen, a.isMinimized)
            guard let window = findOrCreate.0 else {
                // we don't know this window, but it got focused, so let's update app.focusedWindow with nil
                if type == kAXFocusedWindowChangedNotification {
                    app.focusedWindow = nil
                }
                return
            }
            Logger.debug { "\(type) win:\(window.debugId)" }
            if findOrCreate.1 {
                App.refreshOpenUiAfterExternalEvent([window])
            }
            if type == kAXMainWindowChangedNotification || type == kAXFocusedWindowChangedNotification {
                focusedWindowChanged(window)
            } else if type == kAXWindowResizedNotification || type == kAXWindowMovedNotification {
                windowResizedOrMoved(window)
            } else if !findOrCreate.1 {
                App.refreshOpenUiAfterExternalEvent([window])
            }
        }
    }

    private static func windowDestroyed(_ windowAxUiElement: AXUIElement, _ pid: pid_t, _ wid: CGWindowID) {
        if let window = (Windows.list.first { $0.isEqualRobust(windowAxUiElement, wid) }) {
            Windows.removeWindows([window], true)
        }
    }

    private static func focusedWindowChanged(_ window: Window) {
        // photoshop will focus a window *after* you focus another app
        // we check that a focused window happens within an active app
        guard window.application.runningApplication.isActive else { return }
        // if the window is shown by alt-tab, we mark it as focused for this app
        // this avoids issues with dialogs, quicklook, etc (see scenarios from #1044 and #2003)
        window.application.focusedWindow = window
        App.checkIfShortcutsShouldBeDisabled(window, nil)
        if let windows = Windows.updateLastFocusOrder(window) {
            App.refreshOpenUiAfterExternalEvent(windows)
        }
    }

    private static func windowResizedOrMoved(_ window: Window) {
        window.updateSpacesAndScreen()
        App.refreshOpenUiAfterExternalEvent([window])
    }
}
