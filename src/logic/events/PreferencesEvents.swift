import Cocoa
import Sparkle

class PreferencesEvents {
    private static var initialized = false
    private static let preferencesRequiringUiReset = [
        "appearanceStyle",
        "appearanceSize",
        "appearanceTheme",
        "showOnScreen",
        "showAppsOrWindows",
    ]
    // docs: https://developer.apple.com/library/archive/technotes/tn2083/_index.html#//apple_ref/doc/uid/DTS10003794-CH1-SECTION23
    // docs: man launchd.plist
    private static let launchAgentPlist: NSDictionary = [
        "Label": App.bundleIdentifier,
        "Program": Bundle.main.executablePath ?? "/Applications/\(App.name).app/Contents/MacOS/\(App.name)",
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
        // starting from macOS 13, AssociatedBundleIdentifiers is required, otherwise the UI in
        // System Settings > General > Login Items, will show "Louis Pontoise" instead of "AltTab.app"
        "AssociatedBundleIdentifiers": App.bundleIdentifier,
        // "ProcessType: If left unspecified, the system will apply light resource limits to the job,
        //               throttling its CPU usage and I/O bandwidth"
        "ProcessType": "Interactive",
        // "LegacyTimers": If this key is set to true, timers created by the job will opt into less
        //                 efficient but more precise behavior and not be coalesced with other timers.
        "LegacyTimers": true,
    ]

    static func initialize() {
        guard !initialized else { return }
        initialized = true
        UserDefaultsEvents.observe()
        ControlsTab.initializePreferencesDependentState()
        applyMenubarPreferencesIfReady()
        applyUpdatePolicyPreference()
        TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            applyStartAtLoginPreference()
        }
    }

    static func preferenceChanged(_ key: String) {
        if !initialized {
            if key == "startAtLogin" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    applyStartAtLoginPreference()
                }
            }
            return
        }
        ControlsTab.preferenceChanged(key)
        switch key {
        case "menubarIcon", "menubarIconShown": applyMenubarPreferencesIfReady()
        case "nextWindowGesture": TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
        case "startAtLogin": applyStartAtLoginPreference()
        case "updatePolicy": applyUpdatePolicyPreference()
        case let k where preferencesRequiringUiReset.contains(k) && TilesPanel.shared != nil: App.resetPreferencesDependentComponents()
        default: break
        }
    }

    private static func applyMenubarPreferencesIfReady() {
        guard Menubar.statusItem != nil else { return }
        Menubar.menubarIconCallback(nil)
    }

    private static func applyUpdatePolicyPreference() {
        GeneralTab.policyLock = true
        let policy = Preferences.updatePolicy
        SUUpdater.shared().automaticallyDownloadsUpdates = policy == .autoInstall
        SUUpdater.shared().automaticallyChecksForUpdates = policy == .autoInstall || policy == .autoCheck
        GeneralTab.policyLock = false
    }

    private static func applyStartAtLoginPreference() {
        var preferenceEnabled = Preferences.startAtLogin
        if (PreferencesEvents.self as AvoidDeprecationWarnings.Type).removeLoginItemIfPresent() && !preferenceEnabled {
            preferenceEnabled = true
            Preferences.set("startAtLogin", "true", false)
        }
        do {
            try writePlistToDisk(preferenceEnabled)
        } catch let error {
            Logger.error { "Failed to write plist file to disk. error:\(error)" }
        }
    }

    private static func writePlistToDisk(_ enabled: Bool) throws {
        var launchAgentsPath = (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? URL(fileURLWithPath: "~/Library", isDirectory: true)
        launchAgentsPath.appendPathComponent("LaunchAgents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: launchAgentsPath.path) {
            try FileManager.default.createDirectory(at: launchAgentsPath, withIntermediateDirectories: false)
            Logger.debug { launchAgentsPath.absoluteString + " created" }
        }
        launchAgentsPath.appendPathComponent("com.lwouis.alt-tab-macos.plist", isDirectory: false)
        if enabled {
            let data = try PropertyListSerialization.data(fromPropertyList: launchAgentPlist, format: .xml, options: 0)
            try data.write(to: launchAgentsPath, options: [.atomic])
            Logger.debug { launchAgentsPath.absoluteString + " written" }
        } else if FileManager.default.fileExists(atPath: launchAgentsPath.path) {
            try FileManager.default.removeItem(at: launchAgentsPath)
            Logger.debug { launchAgentsPath.absoluteString + " removed" }
        }
    }

    @available(OSX, deprecated: 10.11)
    fileprivate static func removeLoginItemIfPresent() -> Bool {
        var removed = false
        if let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue(),
           let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] {
            let appUrl = URL(fileURLWithPath: Bundle.main.bundlePath)
            for item in loginItemsSnapshot {
                let itemUrl = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as? URL
                if itemUrl?.lastPathComponent == appUrl.lastPathComponent {
                    LSSharedFileListItemRemove(loginItems, item)
                    removed = true
                }
            }
        }
        return removed
    }
}

fileprivate protocol AvoidDeprecationWarnings {
    static func removeLoginItemIfPresent() -> Bool
}

extension PreferencesEvents: AvoidDeprecationWarnings {}
