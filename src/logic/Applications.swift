import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()
    // Set of canonical names (localizedName) that appear more than once among running apps
    static var duplicateCanonicalNames = Set<String>()

    static func initialDiscovery() {
        addInitialRunningApplications()
        RunningApplicationsEvents.observe()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications)
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication]) {
        runningApps.forEach {
            let bundleIdentifier = $0.bundleIdentifier
            let processIdentifier = $0.processIdentifier
            if bundleIdentifier == "com.apple.dock" {
                DockEvents.observe(processIdentifier)
            }
            if isActualApplication(processIdentifier, bundleIdentifier) {
                Applications.list.append(Application($0))
            }
        }
        recomputeDuplicateNamesAndRefreshIfChanged()
    }

    static func removeRunningApplications(_ terminatingApps: [NSRunningApplication]) {
        let existingAppsToRemove = list.filter { app in terminatingApps.contains { tApp in app.runningApplication.isEqual(tApp) } }
        let existingWindowstoRemove = Windows.list.filter { window in terminatingApps.contains { tApp in window.application.runningApplication.isEqual(tApp) } }
        if existingAppsToRemove.isEmpty && existingWindowstoRemove.isEmpty { return }
        var windowsOnTheLeftOfFocusedWindow = 0
        for tApp in terminatingApps {
            for (index, window) in Windows.list.enumerated() {
                if window.application.runningApplication.isEqual(tApp)
                       && index < Windows.focusedWindowIndex && window.shouldShowTheUser {
                    windowsOnTheLeftOfFocusedWindow += 1
                }
            }
            // comparing pid here can fail here, as it can be already nil; we use isEqual here to avoid the issue
            Applications.list.removeAll { $0.runningApplication.isEqual(tApp) }
            Windows.list.removeAll { $0.application.runningApplication.isEqual(tApp) }
        }
        if Windows.list.count == 0 {
            App.app.hideUi()
        } else {
            if windowsOnTheLeftOfFocusedWindow > 0 {
                Windows.cycleFocusedWindowIndex(-windowsOnTheLeftOfFocusedWindow)
            }
            if !existingWindowstoRemove.isEmpty {
                App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
            }
        }
        recomputeDuplicateNamesAndRefreshIfChanged()
    }

    static func refreshBadgesAsync() {
        if !App.app.appIsBeingUsed || Preferences.hideAppBadges { return }
        AXUIElement.retryAxCallUntilTimeout {
            if let dockPid = (list.first { $0.bundleIdentifier == "com.apple.dock" }?.pid),
               let axList = (try AXUIElementCreateApplication(dockPid).children()?.first { try $0.role() == kAXListRole }),
               let axAppDockItem = (try axList.children()?.filter { try $0.subrole() == kAXApplicationDockItemSubrole && ($0.appIsRunning() ?? false) }) {
                let axAppDockItemUrlAndLabel = try axAppDockItem.map { try ($0.attribute(kAXURLAttribute, URL.self), $0.attribute(kAXStatusLabelAttribute, String.self)) }
                DispatchQueue.main.async {
                    refreshBadges_(axAppDockItemUrlAndLabel)
                }
            }
        }
    }

    static func refreshBadges_(_ items: [(URL?, String?)]) {
        Windows.list.enumerated().forEach { (i, window) in
            if !App.app.appIsBeingUsed { return }
            let view = ThumbnailsView.recycledViews[i]
            if let app = Applications.find(window.application.pid) {
                if app.runningApplication.activationPolicy == .regular,
                   let matchingItem = (items.first { $0.0 == app.bundleURL }),
                   let label = matchingItem.1 {
                    app.dockLabel = label
                    view.updateDockLabelIcon(label)
                } else {
                    app.dockLabel = nil
                    assignIfDifferent(&view.dockLabelIcon.isHidden, true)
                }
            }
        }
    }

    private static func isActualApplication(_ processIdentifier: pid_t, _ bundleIdentifier: String?) -> Bool {
        // an app can start with .activationPolicy == .prohibited, then transition to != .prohibited later
        // an app can be both activationPolicy == .accessory and XPC (e.g. com.apple.dock.etci)
        return (isNotXpc(processIdentifier) || isPasswords(bundleIdentifier) || isAndroidEmulator(bundleIdentifier, processIdentifier)) && !processIdentifier.isZombie()
    }

    private static func isNotXpc(_ processIdentifier: pid_t) -> Bool {
        // these private APIs are more reliable than Bundle.init? as it can return nil (e.g. for com.apple.dock.etci)
        var psn = ProcessSerialNumber()
        GetProcessForPID(processIdentifier, &psn)
        var info = ProcessInfoRec()
        GetProcessInformation(&psn, &info)
        return String(info.processType) != "XPC!"
    }

    private static func isPasswords(_ bundleIdentifier: String?) -> Bool {
        return bundleIdentifier == "com.apple.Passwords"
    }

    static func isAndroidEmulator(_ bundleIdentifier: String?, _ processIdentifier: pid_t) -> Bool {
        // NSRunningApplication provides no way to identify the emulator; we pattern match on its KERN_PROCARGS
        if bundleIdentifier == nil,
           let executablePath = Sysctl.run([CTL_KERN, KERN_PROCARGS, processIdentifier]) {
            // example path: ~/Library/Android/sdk/emulator/qemu/darwin-x86_64/qemu-system-x86_64
            return executablePath.range(of: "qemu-system[^/]*$", options: .regularExpression, range: nil, locale: nil) != nil
        }
        return false
    }

    static func find(_ pid: pid_t?) -> Application? {
        return list.first { $0.pid == pid }
    }

    private static func recomputeDuplicateNamesAndRefreshIfChanged() {
        let names = list.compactMap { $0.localizedName }.filter { !$0.isEmpty }
        var counts = [String: Int]()
        for n in names { counts[n, default: 0] += 1 }
        let newSet = Set(counts.filter { $0.value > 1 }.map { $0.key })
        if newSet != duplicateCanonicalNames {
            duplicateCanonicalNames = newSet
            DispatchQueue.main.async {
                App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
            }
        }
    }
}
