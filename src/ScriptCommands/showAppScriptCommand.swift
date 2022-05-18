// used by DockAltTab - show window previews for a specific app (1st window highlighted), ignoring blacklist
import Foundation
import Cocoa

class showAppScriptCommand: NSScriptCommand {
	override func performDefaultImplementation() -> Any? {
        let tarBID = self.evaluatedArguments!["appBID"] as! String
        if (tarBID.trimmingCharacters(in: .whitespacesAndNewlines) == "") { // validate tarBID
            print("tarBID is blank")
            return self
        }
        let appInstances = NSRunningApplication.runningApplications(withBundleIdentifier: tarBID)
        if appInstances.count == 0 {
            print("tarBID '" + tarBID + "' not running")
            return self
        }
        let tarApp = appInstances[0]
        App.app.appIsBeingUsed = true /* actually line 1 of showUI() */
        if App.app.isFirstSummon { // begin follow/modify showUIOrCycleSelection
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            App.app.isFirstSummon = false
            if Windows.list.count == 0 || CGWindow.isMissionControlActive() { App.app.hideUi(); return self }
            Spaces.refreshAllIdsAndIndexes()
            Windows.updateSpaces()
            let screen = NSScreen.preferred()
            (Preferences.appsToShow[0] == .active) ? (App.app.shortcutIndex = 0) : (App.app.shortcutIndex = 1)
            Windows.list.forEach { (window: Window) in // follow refreshWhichWindowsToShowTheUser
                window.shouldShowTheUser =
//                    !(window.application.runningApplication.bundleIdentifier.flatMap { id in Preferences.dontShowBlacklist.contains { id.hasPrefix($0) } } ?? false) &&
                    !(/* Preferences.appsToShow[App.app.shortcutIndex] == .active && */ window.application.runningApplication.processIdentifier != tarApp.processIdentifier) && // -and change line: (active app) pid ==> (target app) pid
                    !(!(Preferences.showHiddenWindows[App.app.shortcutIndex] != .hide) && window.isHidden) &&
                    ((!Preferences.hideWindowlessApps && window.isWindowlessApp) ||
                        !window.isWindowlessApp &&
                        !(!(Preferences.showFullscreenWindows[App.app.shortcutIndex] != .hide) && window.isFullscreen) &&
                        !(!(Preferences.showMinimizedWindows[App.app.shortcutIndex] != .hide) && window.isMinimized) &&
                        !(Preferences.spacesToShow[App.app.shortcutIndex] == .visible && !Spaces.visibleSpaces.contains(window.spaceId)) &&
                        !(Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab && !window.isOnScreen(screen)) &&
                        (Preferences.showTabsAsWindows || !window.isTabbed))
            }
            Windows.reorderList()
            if (!Windows.list.contains { $0.shouldShowTheUser }) { App.app.hideUi(); return self }
            Windows.setInitialFocusedWindowIndex()
            App.app.delayedDisplayScheduled += 1
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) { () -> () in
                if App.app.delayedDisplayScheduled == 1 {
                    App.app.rebuildUi(screen)
                }
                App.app.delayedDisplayScheduled -= 1
            }
        } else {
            App.app.cycleSelection(.leading)
            KeyRepeatTimer.toggleRepeatingKeyNextWindow()
        } // stop following showUIOrCycleSelection
        
        // make sure focus is on 1st window
        App.app.previousWindowShortcutWithRepeatingKey()
        
        
        //follow hideUI
//        App.app.appIsBeingUsed = false
//        App.app.isFirstSummon = true
//        MouseEvents.toggle(false)
//        App.app.hideThumbnailPanelWithoutChangingKeyWindow()
        return self
	}
}
