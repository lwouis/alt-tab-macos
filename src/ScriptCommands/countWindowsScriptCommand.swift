// used by cmd-shift-w / cmd-w applescript replacements to count windows in ALL spaces (so that if there are 0, we can close apps once they hit 0 windows ala Windows™️)
import Foundation
import Cocoa

class countWindowsScriptCommand: NSScriptCommand {
	override func performDefaultImplementation() -> Any? {
        let tarBID = self.evaluatedArguments!["appBID"] as! String
        if (tarBID.trimmingCharacters(in: .whitespacesAndNewlines) == "") { // validate tarBID
            print("tarBID is blank")
            return 0
        }
        let appInstances = NSRunningApplication.runningApplications(withBundleIdentifier: tarBID)
        if appInstances.count == 0 {
            print("tarBID '" + tarBID + "' not running")
            return 0
        }
        let tarApp = appInstances[0]
        var winCount = 0
        Windows.list.forEach { (window: Window) in // follow refreshWhichWindowsToShowTheUser
            if (
//                !(window.application.runningApplication.bundleIdentifier.flatMap { id in Preferences.dontShowBlacklist.contains { id.hasPrefix($0) } } ?? false) &&
                !(/* Preferences.appsToShow[App.app.shortcutIndex] == .active && */ window.application.runningApplication.processIdentifier != tarApp.processIdentifier) /*&&*/ // -and change line: (active app) pid ==> (target app) pid
//                    && ((!Preferences.hideWindowlessApps && window.isWindowlessApp) ||
                    
//                    !window.isWindowlessApp &&
//                    !(Preferences.spacesToShow[App.app.shortcutIndex] == .visible && !Spaces.visibleSpaces.contains(window.spaceId)) &&
//                    (Preferences.showTabsAsWindows || !window.isTabbed))
            ) {winCount += 1}
        }
        return winCount
	}
}
