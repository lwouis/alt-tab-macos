import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXNotificationConstants

class AccessibilityEvents {
    static let axObserverCallback: AXObserverCallback = { _, element, notificationName, refcon in
        let type = notificationName as String
        Logger.debug { type }
        // The subscription baked the owning (pid, wid) into `refcon`, so we get the identity without an
        // AX round-trip. Window-level subs carry a real wid; app-level subs carry wid 0 (their subject
        // window varies per event, so focus/main/created still resolve it from `element`).
        let (pid, wid) = decodeSubscriptionRefcon(refcon)
        // Fast path: focus/activation are edge-triggered — they carry MRU-ordering info that can't be
        // re-queried and must land before the next switcher summon. Update order on a dedicated serial
        // queue, IPC-free, so it's never stuck behind the bulk window-refresh on the AX-query pools.
        updateFocusOrderFastLane(type, element, pid, wid)
        AXCallScheduler.shared.submit {
            do { try handleEvent(type, element, pid, wid) }
            catch { Logger.debug { "handleEvent threw for \(type): stale element" } }
        }
    }

    /// Bake (pid, wid) into a subscription's refcon (see `AXUIElement.subscribeToNotification`). Window-level
    /// subscriptions pass a real wid; app-level subscriptions pass wid 0 (their subject window is per-event).
    static func subscriptionRefcon(_ pid: pid_t, _ wid: CGWindowID = 0) -> UnsafeMutableRawPointer? {
        let packed = (UInt(UInt32(bitPattern: pid)) << 32) | UInt(wid)
        return UnsafeMutableRawPointer(bitPattern: packed)
    }

    private static func decodeSubscriptionRefcon(_ refcon: UnsafeMutableRawPointer?) -> (pid: pid_t, wid: CGWindowID) {
        let packed = UInt(bitPattern: refcon)
        return (pid_t(bitPattern: UInt32(truncatingIfNeeded: packed >> 32)), CGWindowID(truncatingIfNeeded: packed))
    }

    /// IPC-free MRU-order update for the edge-triggered focus events. Window focus/main → bump the
    /// (already-known) window to lastFocusOrder 0. App activation → refresh `frontmostPid`. Unknown
    /// windows are left to the `handleEvent` pipeline below (which discovers them with an AX read).
    private static func updateFocusOrderFastLane(_ type: String, _ element: AXUIElement, _ refconPid: pid_t, _ refconWid: CGWindowID) {
        switch type {
            case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
                BackgroundWork.focusOrderQueue.addOperation {
                    let wid = refconWid != 0 ? refconWid : ((try? element.cgWindowId()) ?? 0)
                    guard wid != 0 else { return }
                    DispatchQueue.main.async {
                        guard let window = Windows.byWindowId[wid],
                              window.application.runningApplication.isActive else { return }
                        focusedWindowChanged(window)
                    }
                }
            case kAXApplicationActivatedNotification:
                guard refconPid != 0 else { return }
                DispatchQueue.main.async { Applications.frontmostPid = refconPid }
            default:
                return
        }
    }

    private static func handleEvent(_ type: String, _ element: AXUIElement, _ refconPid: pid_t, _ refconWid: CGWindowID) throws {
        // identity comes from the subscription refcon; fall back to an AX round-trip only when it didn't
        // carry it — pid for legacy/nil-refcon subs, wid for the app-level focus/main/created events.
        let pid = refconPid != 0 ? refconPid : (try element.pid())
        Logger.debug { "\(type) pid:\(pid)" }
        if AxEventRouting.isAppEvent(type) {
            // dedupKey separates non-interchangeable app work (activate vs visibility) so the scheduler's
            // in-flight de-dup can't drop one; manuallyUpdateWindows' bare "pid-…" key never collides.
            AXCallScheduler.shared.schedule(key: AxEventRouting.dedupKey(type, pid: pid, wid: 0), context: "(pid:\(pid))", pid: pid) {
                try handleEventApp(type, pid, element)
            }
        } else {
            let wid = refconWid != 0 ? refconWid : ((try? element.cgWindowId()) ?? 0)
            guard wid != 0 || type == kAXUIElementDestroyedNotification,
                  wid != TilesPanel.shared.windowNumber else { return }
            if type == kAXUIElementDestroyedNotification {
                DispatchQueue.main.async {
                    Logger.info { "\(type) wid:\(wid) pid:\(pid)" }
                    windowDestroyed(element, pid, wid)
                }
                return
            }
            let read = {
                AXCallScheduler.shared.schedule(key: AxEventRouting.dedupKey(type, pid: pid, wid: wid), context: "(pid:\(pid) wid:\(wid))", pid: pid) {
                    try handleEventWindow(type, wid, pid, element)
                }
            }
            // coalesce the self-flooding events to ≤1 attribute read per window per 200ms (before the read);
            // edge-triggered events (created/minimized/deminimized/focus/main) run promptly.
            if AxEventRouting.coalesces(type) {
                Applications.windowAttributesThrottler.throttleOrProceed(key: "\(wid)", read)
            } else {
                read()
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
            AXCallScheduler.shared.schedule(key: "wid-\(wid)-focus", context: "\(type) \(app.debugId))", pid: pid) {
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
        // if we process the "shown" event too fast, UI may not be ready; we add a delay to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            App.refreshOpenUiAfterExternalEvent(windows)
        }
    }

    static func handleEventWindow(_ type: String, _ wid: CGWindowID, _ pid: pid_t, _ element: AXUIElement) throws {
        let level = wid.level()
        // if we query .children on ourselves, AppKit calls layout directly from our thread instead of IPC; we avoid this
        let isSelf = pid == ProcessInfo.processInfo.processIdentifier
        let keys = [kAXTitleAttribute, kAXSubroleAttribute, kAXRoleAttribute, kAXSizeAttribute, kAXPositionAttribute, kAXFullscreenAttribute, kAXMinimizedAttribute, kAXMainAttribute] + (isSelf ? [] : [kAXChildrenAttribute])
        let a = try element.attributes(keys)
        let tabSiblingTitles = isSelf ? nil : TabGroup.extractTabTitles(a.children)
        DispatchQueue.main.async {
            guard let app = Applications.findOrCreate(pid, false) else { return }
            Logger.info { "\(type) wid:\(wid) app:\(app.debugId)" }
            let findOrCreate = Windows.findOrCreate(element, wid, app, level, a.title, a.subrole, a.role, a.size, a.position, a.isFullscreen, a.isMinimized)
            guard let window = findOrCreate.0 else {
                // we don't know this window, but it got focused, so let's update app.focusedWindow with nil
                if type == kAXFocusedWindowChangedNotification && a.role != kAXSheetRole {
                    app.focusedWindow = nil
                }
                return
            }
            window.isMainWindow = a.isMain ?? false
            Logger.debug { "\(type) win:\(window.debugId)" }
            var tabStateChanged = false
            if tabSiblingTitles != nil || window.tabbedSiblingWids != nil {
                tabStateChanged = TabGroup.updateState(window, tabSiblingTitles)
            }
            if findOrCreate.1 || (tabStateChanged && SwitcherSession.isActive) {
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
        // a move can change the window's Space; fetch it off-main (this runs on main) then apply + refresh
        guard let wid = window.cgWindowId else { App.refreshOpenUiAfterExternalEvent([window]); return }
        CGSCallScheduler.windowSpaces(wid) { spaceIds in
            window.applySpacesAndScreen([wid: spaceIds])
            App.refreshOpenUiAfterExternalEvent([window])
        }
    }
}
