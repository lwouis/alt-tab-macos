import Cocoa
import Sparkle

/// Side-effect dispatcher for preference changes. Each branch of `preferenceChanged(_:)`
/// calls into a domain-specific owner (Menubar, TrackpadEvents, SparkleDelegate, LoginItem,
/// ProFeature) rather than implementing the side effect inline. Over time each call-site
/// should subscribe directly to its own preference; this file is a transition scaffold.
class PreferencesEvents {
    private static var initialized = false
    private static let preferencesRequiringUiReset = [
        "appearanceStyle",
        "appearanceSize",
        "appearanceTheme",
        "showOnScreen",
    ]

    /// True if `key` is an indexed override of one of the 5 overridable appearance prefs
    /// (e.g. `appearanceStyleOverride2`). Used to trigger a UI reset and override-label refresh
    /// when an override changes, so the switcher and Settings UI both pick up the new value.
    private static func isOverrideKey(_ key: String) -> Bool {
        for baseName in Preferences.appearanceOverrideBaseNames {
            for i in 0...Preferences.maxShortcutCount {
                if Preferences.indexToName(baseName, i) == key { return true }
            }
        }
        return false
    }

    /// True if `key` is an indexed per-shortcut grouping pref (`showAppsOrWindows`, `showTabsAsWindows`
    /// + index suffix). These moved from global to per-shortcut, so a change on any index needs the
    /// same UI reset that the old global key used to trigger.
    private static func isPerShortcutGroupingKey(_ key: String) -> Bool {
        for baseName in ["showAppsOrWindows", "showTabsAsWindows"] {
            for i in 0...Preferences.maxShortcutCount {
                if Preferences.indexToName(baseName, i) == key { return true }
            }
        }
        return false
    }

    static func initialize() {
        guard !initialized else { return }
        initialized = true
        UserDefaultsEvents.observe()
        ControlsTab.initializePreferencesDependentState()
        applyUpdatePolicyPreference()
        TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            LoginItem.applyCurrentPreference()
        }
    }

    static func preferenceChanged(_ key: String) {
        if !initialized {
            if key == "startAtLogin" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    LoginItem.applyCurrentPreference()
                }
            }
            return
        }
        if LicenseManager.shared.isProLocked && ProFeature.isStoredValuePro(preferenceKey: key) {
            UpgradeTab.navigateToUpgradeTab()
        }
        ControlsTab.preferenceChanged(key)
        switch key {
        case "menubarIcon", "menubarIconShown": applyMenubarPreferencesIfReady()
        case "nextWindowGesture": TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
        case "startAtLogin": LoginItem.applyCurrentPreference()
        case "updatePolicy": applyUpdatePolicyPreference()
        case let k where preferencesRequiringUiReset.contains(k) && TilesPanel.shared != nil: App.resetPreferencesDependentComponents()
        case let k where (isOverrideKey(k) || isPerShortcutGroupingKey(k)) && TilesPanel.shared != nil: App.resetPreferencesDependentComponents()
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
        App.updaterController?.updater.automaticallyDownloadsUpdates = policy == .autoInstall
        App.updaterController?.updater.automaticallyChecksForUpdates = policy == .autoInstall || policy == .autoCheck
        GeneralTab.policyLock = false
    }
}
