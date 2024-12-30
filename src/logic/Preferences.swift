import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class Preferences {
    // default values
    static var defaultValues: [String: String] = [
        "holdShortcut": "⌥",
        "holdShortcut2": "⌥",
        "holdShortcut3": "⌥",
        "nextWindowShortcut": "⇥",
        "nextWindowShortcut2": keyAboveTabDependingOnInputSource(),
        "nextWindowShortcut3": "",
        "nextWindowGesture": GesturePreference.disabled.indexAsString,
        "focusWindowShortcut": "Space",
        "previousWindowShortcut": "⇧",
        "cancelShortcut": "⎋",
        "closeWindowShortcut": "W",
        "minDeminWindowShortcut": "M",
        "toggleFullscreenWindowShortcut": "F",
        "quitAppShortcut": "Q",
        "hideShowAppShortcut": "H",
        "arrowKeysEnabled": "true",
        "vimKeysEnabled": "false",
        "mouseHoverEnabled": "false",
        "cursorFollowFocusEnabled": "false",
        "showMinimizedWindows": ShowHowPreference.show.indexAsString,
        "showMinimizedWindows2": ShowHowPreference.show.indexAsString,
        "showMinimizedWindows3": ShowHowPreference.show.indexAsString,
        "showMinimizedWindows4": ShowHowPreference.show.indexAsString,
        "showHiddenWindows": ShowHowPreference.show.indexAsString,
        "showHiddenWindows2": ShowHowPreference.show.indexAsString,
        "showHiddenWindows3": ShowHowPreference.show.indexAsString,
        "showHiddenWindows4": ShowHowPreference.show.indexAsString,
        "showFullscreenWindows": ShowHowPreference.show.indexAsString,
        "showFullscreenWindows2": ShowHowPreference.show.indexAsString,
        "showFullscreenWindows3": ShowHowPreference.show.indexAsString,
        "showFullscreenWindows4": ShowHowPreference.show.indexAsString,
        "windowOrder": WindowOrderPreference.recentlyFocused.indexAsString,
        "windowOrder2": WindowOrderPreference.recentlyFocused.indexAsString,
        "windowOrder3": WindowOrderPreference.recentlyFocused.indexAsString,
        "windowOrder4": WindowOrderPreference.recentlyFocused.indexAsString,
        "showTabsAsWindows": "false",
        "hideColoredCircles": "false",
        "windowDisplayDelay": "100",
        "appearanceStyle": AppearanceStylePreference.thumbnails.indexAsString,
        "appearanceSize": AppearanceSizePreference.medium.indexAsString,
        "appearanceTheme": AppearanceThemePreference.system.indexAsString,
        "appearanceVisibility": AppearanceVisibilityPreference.normal.indexAsString,
        "theme": ThemePreference.macOs.indexAsString,
        "showOnScreen": ShowOnScreenPreference.active.indexAsString,
        "titleTruncation": TitleTruncationPreference.end.indexAsString,
        "alignThumbnails": AlignThumbnailsPreference.center.indexAsString,
        "showAppsOrWindows": ShowAppsOrWindowsPreference.windows.indexAsString,
        "showTitles": ShowTitlesPreference.windowTitle.indexAsString,
        "appsToShow": AppsToShowPreference.all.indexAsString,
        "appsToShow2": AppsToShowPreference.active.indexAsString,
        "appsToShow3": AppsToShowPreference.all.indexAsString,
        "appsToShow4": AppsToShowPreference.all.indexAsString,
        "spacesToShow": SpacesToShowPreference.all.indexAsString,
        "spacesToShow2": SpacesToShowPreference.all.indexAsString,
        "spacesToShow3": SpacesToShowPreference.all.indexAsString,
        "spacesToShow4": SpacesToShowPreference.all.indexAsString,
        "screensToShow": ScreensToShowPreference.all.indexAsString,
        "screensToShow2": ScreensToShowPreference.all.indexAsString,
        "screensToShow3": ScreensToShowPreference.all.indexAsString,
        "screensToShow4": ScreensToShowPreference.all.indexAsString,
        "fadeOutAnimation": "false",
        "hideSpaceNumberLabels": "false",
        "hideStatusIcons": "false",
        "startAtLogin": "true",
        "menubarIcon": MenubarIconPreference.outlined.indexAsString,
        "menubarIconShown": "true",
        "language": LanguagePreference.systemDefault.indexAsString,
        "blacklist": defaultBlacklist(),
        "updatePolicy": UpdatePolicyPreference.autoCheck.indexAsString,
        "crashPolicy": CrashPolicyPreference.ask.indexAsString,
        "shortcutStyle": ShortcutStylePreference.focusOnRelease.indexAsString,
        "shortcutStyle2": ShortcutStylePreference.focusOnRelease.indexAsString,
        "shortcutStyle3": ShortcutStylePreference.focusOnRelease.indexAsString,
        "shortcutStyle4": ShortcutStylePreference.focusOnRelease.indexAsString,
        "hideAppBadges": "false",
        "hideWindowlessApps": "false",
        "hideThumbnails": "false",
        "previewFocusedWindow": "false",
        "screenRecordingPermissionSkipped": "false",
    ]

    // system preferences
    static var finderShowsQuitMenuItem: Bool { UserDefaults(suiteName: "com.apple.Finder")?.bool(forKey: "QuitMenuItem") ?? false }

    // constant values
    // not exposed as preferences now but may be in the future, probably through macro preferences

    // persisted values
    static var holdShortcut: [String] { ["holdShortcut", "holdShortcut2", "holdShortcut3"].map { UserDefaults.standard.string($0) } }
    static var nextWindowShortcut: [String] { ["nextWindowShortcut", "nextWindowShortcut2", "nextWindowShortcut3"].map { UserDefaults.standard.string($0) } }
    static var nextWindowGesture: GesturePreference { UserDefaults.standard.macroPref("nextWindowGesture", GesturePreference.allCases) }
    static var focusWindowShortcut: String { UserDefaults.standard.string("focusWindowShortcut") }
    static var previousWindowShortcut: String { UserDefaults.standard.string("previousWindowShortcut") }
    static var cancelShortcut: String { UserDefaults.standard.string("cancelShortcut") }
    static var closeWindowShortcut: String { UserDefaults.standard.string("closeWindowShortcut") }
    static var minDeminWindowShortcut: String { UserDefaults.standard.string("minDeminWindowShortcut") }
    static var toggleFullscreenWindowShortcut: String { UserDefaults.standard.string("toggleFullscreenWindowShortcut") }
    static var quitAppShortcut: String { UserDefaults.standard.string("quitAppShortcut") }
    static var hideShowAppShortcut: String { UserDefaults.standard.string("hideShowAppShortcut") }
    // periphery:ignore
    static var arrowKeysEnabled: Bool { UserDefaults.standard.bool("arrowKeysEnabled") }
    // periphery:ignore
    static var vimKeysEnabled: Bool { UserDefaults.standard.bool("vimKeysEnabled") }
    static var mouseHoverEnabled: Bool { UserDefaults.standard.bool("mouseHoverEnabled") }
    static var cursorFollowFocusEnabled: Bool { UserDefaults.standard.bool("cursorFollowFocusEnabled") }
    static var showTabsAsWindows: Bool { UserDefaults.standard.bool("showTabsAsWindows") }
    static var hideColoredCircles: Bool { UserDefaults.standard.bool("hideColoredCircles") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(UserDefaults.standard.int("windowDisplayDelay")) }
    static var fadeOutAnimation: Bool { UserDefaults.standard.bool("fadeOutAnimation") }
    static var hideSpaceNumberLabels: Bool { UserDefaults.standard.bool("hideSpaceNumberLabels") }
    static var hideStatusIcons: Bool { UserDefaults.standard.bool("hideStatusIcons") }
    static var hideAppBadges: Bool { UserDefaults.standard.bool("hideAppBadges") }
    static var hideWindowlessApps: Bool { UserDefaults.standard.bool("hideWindowlessApps") }
    // periphery:ignore
    static var startAtLogin: Bool { UserDefaults.standard.bool("startAtLogin") }
    static var blacklist: [BlacklistEntry] { UserDefaults.standard.json("blacklist", [BlacklistEntry].self) }
    static var previewFocusedWindow: Bool { UserDefaults.standard.bool("previewFocusedWindow") }
    static var screenRecordingPermissionSkipped: Bool { UserDefaults.standard.bool("screenRecordingPermissionSkipped") }

    // macro values
    static var appearanceStyle: AppearanceStylePreference { UserDefaults.standard.macroPref("appearanceStyle", AppearanceStylePreference.allCases) }
    static var appearanceSize: AppearanceSizePreference { UserDefaults.standard.macroPref("appearanceSize", AppearanceSizePreference.allCases) }
    static var appearanceTheme: AppearanceThemePreference { UserDefaults.standard.macroPref("appearanceTheme", AppearanceThemePreference.allCases) }
    static var appearanceVisibility: AppearanceVisibilityPreference { UserDefaults.standard.macroPref("appearanceVisibility", AppearanceVisibilityPreference.allCases) }
    // periphery:ignore
    static var theme: ThemePreference { ThemePreference.macOs/*UserDefaults.standard.macroPref("theme", ThemePreference.allCases)*/ }
    static var showOnScreen: ShowOnScreenPreference { UserDefaults.standard.macroPref("showOnScreen", ShowOnScreenPreference.allCases) }
    static var titleTruncation: TitleTruncationPreference { UserDefaults.standard.macroPref("titleTruncation", TitleTruncationPreference.allCases) }
    static var alignThumbnails: AlignThumbnailsPreference { UserDefaults.standard.macroPref("alignThumbnails", AlignThumbnailsPreference.allCases) }
    static var showAppsOrWindows: ShowAppsOrWindowsPreference { UserDefaults.standard.macroPref("showAppsOrWindows", ShowAppsOrWindowsPreference.allCases) }
    static var showTitles: ShowTitlesPreference { UserDefaults.standard.macroPref("showTitles", ShowTitlesPreference.allCases) }
    static var updatePolicy: UpdatePolicyPreference { UserDefaults.standard.macroPref("updatePolicy", UpdatePolicyPreference.allCases) }
    static var crashPolicy: CrashPolicyPreference { UserDefaults.standard.macroPref("crashPolicy", CrashPolicyPreference.allCases) }
    static var appsToShow: [AppsToShowPreference] { ["appsToShow", "appsToShow2", "appsToShow3", "appsToShow4"].map { UserDefaults.standard.macroPref($0, AppsToShowPreference.allCases) } }
    static var spacesToShow: [SpacesToShowPreference] { ["spacesToShow", "spacesToShow2", "spacesToShow3", "spacesToShow4"].map { UserDefaults.standard.macroPref($0, SpacesToShowPreference.allCases) } }
    static var screensToShow: [ScreensToShowPreference] { ["screensToShow", "screensToShow2", "screensToShow3", "screensToShow4"].map { UserDefaults.standard.macroPref($0, ScreensToShowPreference.allCases) } }
    static var showMinimizedWindows: [ShowHowPreference] { ["showMinimizedWindows", "showMinimizedWindows2", "showMinimizedWindows3", "showMinimizedWindows4"].map { UserDefaults.standard.macroPref($0, ShowHowPreference.allCases) } }
    static var showHiddenWindows: [ShowHowPreference] { ["showHiddenWindows", "showHiddenWindows2", "showHiddenWindows3", "showHiddenWindows4"].map { UserDefaults.standard.macroPref($0, ShowHowPreference.allCases) } }
    static var showFullscreenWindows: [ShowHowPreference] { ["showFullscreenWindows", "showFullscreenWindows2", "showFullscreenWindows3", "showFullscreenWindows4"].map { UserDefaults.standard.macroPref($0, ShowHowPreference.allCases) } }
    static var windowOrder: [WindowOrderPreference] { ["windowOrder", "windowOrder2", "windowOrder3", "windowOrder4"].map { UserDefaults.standard.macroPref($0, WindowOrderPreference.allCases) } }
    static var shortcutStyle: [ShortcutStylePreference] { ["shortcutStyle", "shortcutStyle2", "shortcutStyle3", "shortcutStyle4"].map { UserDefaults.standard.macroPref($0, ShortcutStylePreference.allCases) } }
    static var menubarIcon: MenubarIconPreference { UserDefaults.standard.macroPref("menubarIcon", MenubarIconPreference.allCases) }
    static var menubarIconShown: Bool { UserDefaults.standard.bool("menubarIconShown") }
    static var language: LanguagePreference { UserDefaults.standard.macroPref("language", LanguagePreference.allCases) }

    static let gestureIndex = 3

    static func initialize() {
        removeCorruptedPreferences()
        migratePreferences()
        registerDefaults()
    }

    static func removeCorruptedPreferences() {
        // from v5.1.0+, there are crash reports of users somehow having their hold shortcuts set to ""
        ["holdShortcut", "holdShortcut2", "holdShortcut3", "holdShortcut4", "holdShortcut5"].forEach {
            if let s = UserDefaults.standard.string(forKey: $0), s == "" {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }
    }

    static func resetAll() {
        UserDefaults.standard.removePersistentDomain(forName: App.id)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaultValues)
    }

    static func getString(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func set<T>(_ key: String, _ value: T) where T: Encodable {
        UserDefaults.standard.set(key == "blacklist" ? jsonEncode(value) : value, forKey: key)
        UserDefaults.cache.removeValue(forKey: key)
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.cache.removeValue(forKey: key)
    }

    static var all: [String: Any] { UserDefaults.standard.persistentDomain(forName: App.id)! }

    static func migratePreferences() {
        let preferencesKey = "preferencesVersion"
        if let versionInPlist = UserDefaults.standard.string(forKey: preferencesKey) {
            if versionInPlist != "#VERSION#" && versionInPlist.compare(App.version, options: .numeric) != .orderedDescending {
                updateToNewPreferences(versionInPlist)
            }
        }
        UserDefaults.standard.set(App.version, forKey: preferencesKey)
    }

    private static func updateToNewPreferences(_ versionInPlist: String) {
        // x.compare(y) is .orderedDescending if x > y
        if versionInPlist.compare("7.13.1", options: .numeric) != .orderedDescending {
            migrateGestures()
            if versionInPlist.compare("7.8.0", options: .numeric) != .orderedDescending {
                migrateMenubarIconWithNewShownToggle()
                if versionInPlist.compare("7.0.0", options: .numeric) != .orderedDescending {
                    migratePreferencesIndexes()
                    if versionInPlist.compare("6.43.0", options: .numeric) != .orderedDescending {
                        migrateBlacklists()
                        if versionInPlist.compare("6.28.1", options: .numeric) != .orderedDescending {
                            migrateMinMaxWindowsWidthInRow()
                            if versionInPlist.compare("6.27.1", options: .numeric) != .orderedDescending {
                                // "Start at login" new implem doesn't use Login Items; we remove the entry from previous versions
                                (Preferences.self as AvoidDeprecationWarnings.Type).migrateLoginItem()
                                if versionInPlist.compare("6.23.0", options: .numeric) != .orderedDescending {
                                    // "Show windows from:" got the "Active Space" option removed
                                    migrateShowWindowsFrom()
                                    if versionInPlist.compare("6.18.1", options: .numeric) != .orderedDescending {
                                        // nextWindowShortcut used to be able to have modifiers already present in holdShortcut; we remove these
                                        migrateNextWindowShortcuts()
                                        // dropdowns preferences used to store English text; now they store indexes
                                        migrateDropdownsFromTextToIndexes()
                                        // the "Hide menubar icon" checkbox was replaced with a dropdown of: icon1, icon2, hidden
                                        migrateMenubarIconFromCheckboxToDropdown()
                                        // "Show minimized/hidden/fullscreen windows" checkboxes were replaced with dropdowns
                                        migrateShowWindowsCheckboxToDropdown()
                                        // "Max size on screen" was split into max width and max height
                                        migrateMaxSizeOnScreenToWidthAndHeight()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // we split gestures from disabled, 3-finger, 4-finger to: disabled, 3-finger-horizontal, 3-finger-vertical, 4-finger-horizontal, 4-finger-vertical
    // no need to map 0 -> 0 (disabled -> disabled)
    // no need to map 1 -> 1 (3-finger -> 3-finger-horizontal)
    // we need to map 2 -> 3 (4-finger -> 4-finger-horizontal)
    private static func migrateGestures() {
        if let old = UserDefaults.standard.string(forKey: "nextWindowGesture") {
            if old == "2" { // 2 (4-finger) -> 3 (4-finger-horizontal)
                UserDefaults.standard.set("3", forKey: "nextWindowGesture")
            }
        }
    }


    // we added the new menubarIconShown toggle. It replaces menubarIcon having value "3" which would hide the icon
    // there are now 2 preferences : menubarIconShown is a boolean, and menubarIcon has values 0, 1, 2
    private static func migrateMenubarIconWithNewShownToggle() {
        if let old = UserDefaults.standard.string(forKey: "menubarIcon") {
            if old == "3" {
                UserDefaults.standard.set("0", forKey: "menubarIcon")
                UserDefaults.standard.set("false", forKey: "menubarIconShown")
            }
        }
    }

    // we want to rely on preferences numbers to match the enum indexes. This migration realigns existing desyncs
    private static func migratePreferencesIndexes() {
        // migrate spacesToShow from 1 to 2. 1 was removed a while ago. 1=active => 2=>visible
        ["", "2", "3", "4", "5"].forEach { suffix in
            if let spacesToShow = UserDefaults.standard.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "1" {
                    UserDefaults.standard.set("2", forKey: "spacesToShow" + suffix)
                }
            }
        }

        // migrate spacesToShow from 0 to 2 and 2 to 0. 0 used to be end, 2 used to be start; they got switch for the UI order
        ["", "2", "3", "4", "5"].forEach { suffix in
            if let spacesToShow = UserDefaults.standard.string(forKey: "titleTruncation" + suffix) {
                if spacesToShow == "0" {
                    UserDefaults.standard.set("2", forKey: "titleTruncation" + suffix)
                }
                if spacesToShow == "2" {
                    UserDefaults.standard.set("0", forKey: "titleTruncation" + suffix)
                }
            }
        }
    }

    private static func migrateBlacklists() {
        var entries = [BlacklistEntry]()
        if let old = UserDefaults.standard.string(forKey: "dontShowBlacklist") {
            entries.append(contentsOf: oldBlacklistEntriesToNewOnes(old, .always, .none))
        }
        if let old = UserDefaults.standard.string(forKey: "disableShortcutsBlacklist") {
            let onlyFullscreen = UserDefaults.standard.bool(forKey: "disableShortcutsBlacklistOnlyFullscreen")
            entries.append(contentsOf: oldBlacklistEntriesToNewOnes(old, .none, onlyFullscreen ? .whenFullscreen : .always))
        }
        if entries.count > 0 {
            UserDefaults.standard.set(Preferences.jsonEncode(entries), forKey: "blacklist")
            ["dontShowBlacklist", "disableShortcutsBlacklist", "disableShortcutsBlacklistOnlyFullscreen"].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }
    }

    private static func oldBlacklistEntriesToNewOnes(_ old: String, _ hide: BlacklistHidePreference, _ ignore: BlacklistIgnorePreference) -> [BlacklistEntry] {
        old.split(separator: "\n").compactMap { (e) -> BlacklistEntry? in
            let line = e.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                return nil
            }
            return BlacklistEntry(bundleIdentifier: line, hide: hide, ignore: ignore)
        }
    }

    private static func migrateMinMaxWindowsWidthInRow() {
        ["windowMinWidthInRow", "windowMaxWidthInRow"].forEach {
            if let old = UserDefaults.standard.string(forKey: $0) {
                if old == "0" {
                    UserDefaults.standard.set("1", forKey: $0)
                }
            }
        }
    }

    @available(OSX, deprecated: 10.11)
    static func migrateLoginItem() {
        do {
            if let loginItemsWrapped = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil) {
                let loginItems = loginItemsWrapped.takeRetainedValue()
                if let loginItemsSnapshotWrapped = LSSharedFileListCopySnapshot(loginItems, nil) {
                    let loginItemsSnapshot = loginItemsSnapshotWrapped.takeRetainedValue() as! [LSSharedFileListItem]
                    let itemName = Bundle.main.bundleURL.lastPathComponent as CFString
                    let itemUrl = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
                    loginItemsSnapshot.forEach {
                        if (LSSharedFileListItemCopyDisplayName($0).takeRetainedValue() == itemName) ||
                               (LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == itemUrl) {
                            LSSharedFileListItemRemove(loginItems, $0)
                        }
                    }
                }
            }
            throw AxError.runtimeError // remove compiler warning
        } catch {
            // the LSSharedFile API is deprecated, and has a runtime crash on M1 Monterey
            // we catch any exception to void the app crashing
        }
    }

    private static func migrateShowWindowsFrom() {
        ["", "2"].forEach { suffix in
            if let spacesToShow = UserDefaults.standard.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "2" {
                    UserDefaults.standard.set("1", forKey: "screensToShow" + suffix)
                    UserDefaults.standard.set("1", forKey: "spacesToShow" + suffix)
                } else if spacesToShow == "1" {
                    UserDefaults.standard.set("1", forKey: "screensToShow" + suffix)
                }
            }
        }
    }

    private static func migrateNextWindowShortcuts() {
        ["", "2"].forEach { suffix in
            if let oldHoldShortcut = UserDefaults.standard.string(forKey: "holdShortcut" + suffix),
               let oldNextWindowShortcut = UserDefaults.standard.string(forKey: "nextWindowShortcut" + suffix) {
                let nextWindowShortcutCleanedUp = oldHoldShortcut.reduce(oldNextWindowShortcut, { $0.replacingOccurrences(of: String($1), with: "") })
                if oldNextWindowShortcut != nextWindowShortcutCleanedUp {
                    UserDefaults.standard.set(nextWindowShortcutCleanedUp, forKey: "nextWindowShortcut" + suffix)
                }
            }
        }
    }

    private static func migrateMaxSizeOnScreenToWidthAndHeight() {
        if let old = UserDefaults.standard.string(forKey: "maxScreenUsage") {
            UserDefaults.standard.set(old, forKey: "maxWidthOnScreen")
            UserDefaults.standard.set(old, forKey: "maxHeightOnScreen")
        }
    }

    private static func migrateShowWindowsCheckboxToDropdown() {
        ["showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows"]
            .flatMap { [$0, $0 + "2"] }
            .forEach {
                if let old = UserDefaults.standard.string(forKey: $0) {
                    if old == "true" {
                        UserDefaults.standard.set(ShowHowPreference.show.indexAsString, forKey: $0)
                    } else if old == "false" {
                        UserDefaults.standard.set(ShowHowPreference.hide.indexAsString, forKey: $0)
                    }
                }
            }
    }

    private static func migrateDropdownsFromTextToIndexes() {
        migratePreferenceValue("theme", [" macOS": "0", "❖ Windows 10": "1"])
        // "Main screen" was renamed to "Active screen"
        migratePreferenceValue("showOnScreen", ["Main screen": "0", "Active screen": "0", "Screen including mouse": "1"])
        migratePreferenceValue("alignThumbnails", ["Left": "0", "Center": "1"])
        migratePreferenceValue("appsToShow", ["All apps": "0", "Active app": "1"])
        migratePreferenceValue("spacesToShow", ["All spaces": "0", "Active space": "1"])
        migratePreferenceValue("screensToShow", ["All screens": "0", "Screen showing AltTab": "1"])
    }

    private static func migrateMenubarIconFromCheckboxToDropdown() {
        if let old = UserDefaults.standard.string(forKey: "hideMenubarIcon") {
            if old == "true" {
                UserDefaults.standard.set("3", forKey: "menubarIcon")
            }
        }
    }

    static func migratePreferenceValue(_ preference: String, _ oldAndNew: [String: String]) {
        if let old = UserDefaults.standard.string(forKey: preference),
           let new = oldAndNew[old] {
            UserDefaults.standard.set(new, forKey: preference)
        }
    }

    static func onlyShowApplications() -> Bool {
        return Preferences.showAppsOrWindows == .applications && Preferences.appearanceStyle != .thumbnails
    }

    /// key-above-tab is ` on US keyboard, but can be different on other keyboards
    static func keyAboveTabDependingOnInputSource() -> String {
        return LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: kVK_ANSI_Grave)) ?? "`"
    }

    static func defaultBlacklist() -> String {
        return jsonEncode([
            BlacklistEntry(bundleIdentifier: "com.McAfee.McAfeeSafariHost", hide: .always, ignore: .none),
            BlacklistEntry(bundleIdentifier: "com.apple.finder", hide: .whenNoOpenWindow, ignore: .none),
        ] + [
            "com.microsoft.rdc.macos",
            "com.teamviewer.TeamViewer",
            "org.virtualbox.app.VirtualBoxVM",
            "com.parallels.",
            "com.citrix.XenAppViewer",
            "com.citrix.receiver.icaviewer.mac",
            "com.nicesoftware.dcvviewer",
            "com.vmware.fusion",
            "com.apple.ScreenSharing",
            "com.utmapp.UTM",
        ].map {
            BlacklistEntry(bundleIdentifier: $0, hide: .none, ignore: .whenFullscreen)
        })
    }

    static func jsonEncode<T>(_ value: T) -> String where T: Encodable {
        return String(data: try! JSONEncoder().encode(value), encoding: .utf8)!
    }

    static func indexToName(_ baseName: String, _ index: Int) -> String {
        return baseName + (index == 0 ? "" : String(index + 1))
    }

    static func nameToIndex(_ name: String) -> Int {
        guard let number = name.last?.wholeNumberValue else { return 0 }
        return number - 1
    }
}

// workaround to silence compiler warning
private protocol AvoidDeprecationWarnings {
    static func migrateLoginItem()
}
extension Preferences: AvoidDeprecationWarnings {
}

// MacroPreference are collection of values derived from a single key
// we don't want to store every value in UserDefaults as the user could change them and contradict the macro
protocol MacroPreference {
    var localizedString: LocalizedString { get }
}

protocol SfSymbolMacroPreference: MacroPreference {
    var symbolName: String { get }
}

struct WidthHeightImage {
    var width: CGFloat
    var height: CGFloat
    var name: String

    init(width: CGFloat = 80, height: CGFloat = 50, name: String) {
        self.width = width
        self.height = height
        self.name = name
    }
}

protocol ImageMacroPreference: MacroPreference {
    var image: WidthHeightImage { get }
}

// periphery:ignore
struct ThemeParameters {
    let label: String
    let cellCornerRadius: CGFloat
    let windowCornerRadius: CGFloat
}

typealias LocalizedString = String

enum MenubarIconPreference: CaseIterable, MacroPreference {
    case outlined
    case filled
    case colored

    var localizedString: LocalizedString {
        switch self {
            // these spaces are different from each other; they have to be unique
            case .outlined: return " "
            case .filled: return " "
            case .colored: return " "
        }
    }
}

enum GesturePreference: CaseIterable, MacroPreference {
    case disabled
    case threeFingerHorizontalSwipe
    case threeFingerVerticalSwipe
    case fourFingerHorizontalSwipe
    case fourFingerVerticalSwipe

    var localizedString: LocalizedString {
        switch self {
            case .disabled: return NSLocalizedString("Disabled", comment: "")
            case .threeFingerHorizontalSwipe: return NSLocalizedString("Horizontal Swipe with Three Fingers", comment: "")
            case .threeFingerVerticalSwipe: return NSLocalizedString("Vertical Swipe with Three Fingers", comment: "")
            case .fourFingerHorizontalSwipe: return NSLocalizedString("Horizontal Swipe with Four Fingers", comment: "")
            case .fourFingerVerticalSwipe: return NSLocalizedString("Vertical Swipe with Four Fingers", comment: "")
        }
    }

    func isHorizontal() -> Bool {
        return self == .threeFingerHorizontalSwipe || self == .fourFingerHorizontalSwipe
    }

    func isThreeFinger() -> Bool {
        return self == .threeFingerHorizontalSwipe || self == .threeFingerVerticalSwipe
    }
}

enum LanguagePreference: CaseIterable, MacroPreference {
    case systemDefault
    case indonesian
    case catalan
    case danish
    case german
    case estonian
    case english
    case spanish
    case french
    case irish
    case galician
    case croatian
    case italian
    case kurdish
    case romanian
    case luxembourgish
    case hungarian
    case dutch
    case norwegianBokmal
    case norwegianNynorsk
    case uzbek
    case polish
    case portuguese
    case portugueseBrasil
    case albanian
    case slovak
    case slovenian
    case finnish
    case swedish
    case vietnamese
    case turkish
    case icelandic
    case czech
    case greek
    case bulgarian
    case russian
    case serbian
    case ukrainian
    case hebrew
    case arabic
    case persian
    case hindi
    case bengali
    case tamil
    case kannada
    case malayalam
    case thai
    case japanese
    case chineseSimplified
    case chineseTraditional
    case korean

    var localizedString: String {
        switch self {
            case .systemDefault:
                return NSLocalizedString("System Default", comment: "")
            case .arabic:
                return "العربية"
            case .bulgarian:
                return "Български"
            case .bengali:
                return "বাংলা"
            case .catalan:
                return "Català"
            case .czech:
                return "Čeština"
            case .danish:
                return "Dansk"
            case .german:
                return "Deutsch"
            case .greek:
                return "Ελληνικά"
            case .english:
                return "English"
            case .spanish:
                return "Español"
            case .estonian:
                return "Eesti keel"
            case .persian:
                return "فارسی"
            case .finnish:
                return "Suomi"
            case .french:
                return "Français"
            case .irish:
                return "Gaeilge"
            case .galician:
                return "Galego"
            case .hebrew:
                return "עִבְרִית"
            case .hindi:
                return "हिन्दी"
            case .croatian:
                return "Hrvatski"
            case .hungarian:
                return "Magyar"
            case .indonesian:
                return "Bahasa Indonesia"
            case .icelandic:
                return "Íslenska"
            case .italian:
                return "Italiano"
            case .japanese:
                return "日本語"
            case .kannada:
                return "ಕನ್ನಡ"
            case .korean:
                return "한국어"
            case .kurdish:
                return "Kurdî"
            case .luxembourgish:
                return "Lëtzebuergesch"
            case .malayalam:
                return "മലയാളം"
            case .norwegianBokmal:
                return "Norsk Bokmål"
            case .dutch:
                return "Nederlands"
            case .norwegianNynorsk:
                return "Norsk Nynorsk"
            case .polish:
                return "Polski"
            case .portuguese:
                return "Português"
            case .portugueseBrasil:
                return "Português (Brasil)"
            case .romanian:
                return "Limba română"
            case .russian:
                return "Русский"
            case .slovak:
                return "Slovenčina"
            case .slovenian:
                return "Slovenščina"
            case .albanian:
                return "Shqip"
            case .serbian:
                return "Српски / Srpski"
            case .swedish:
                return "Svenska"
            case .tamil:
                return "தமிழ்"
            case .thai:
                return "ภาษาไทย"
            case .turkish:
                return "Türkçe"
            case .ukrainian:
                return "Українська"
            case .uzbek:
                return "Oʻzbekcha"
            case .vietnamese:
                return "Tiếng Việt"
            case .chineseSimplified:
                return "简体中文"
            case .chineseTraditional:
                return "繁體中文"
        }
    }

    var appleLanguageCode: String? {
        switch self {
            case .systemDefault:
                return nil
            case .arabic:
                return "ar"
            case .bulgarian:
                return "bg"
            case .bengali:
                return "bn"
            case .catalan:
                return "ca"
            case .czech:
                return "cs"
            case .danish:
                return "da"
            case .german:
                return "de"
            case .greek:
                return "el"
            case .english:
                return "en"
            case .spanish:
                return "es"
            case .estonian:
                return "et"
            case .persian:
                return "fa"
            case .finnish:
                return "fi"
            case .french:
                return "fr"
            case .irish:
                return "ga"
            case .galician:
                return "gl"
            case .hebrew:
                return "he"
            case .hindi:
                return "hi"
            case .croatian:
                return "hr"
            case .hungarian:
                return "hu"
            case .indonesian:
                return "id"
            case .icelandic:
                return "is"
            case .italian:
                return "it"
            case .japanese:
                return "ja"
            case .kannada:
                return "kn"
            case .korean:
                return "ko"
            case .kurdish:
                return "ku"
            case .luxembourgish:
                return "lb"
            case .malayalam:
                return "ml"
            case .norwegianBokmal:
                return "nb"
            case .dutch:
                return "nl"
            case .norwegianNynorsk:
                return "nn"
            case .polish:
                return "pl"
            case .portuguese:
                return "pt"
            case .portugueseBrasil:
                return "pt-BR"
            case .romanian:
                return "ro"
            case .russian:
                return "ru"
            case .slovak:
                return "sk"
            case .slovenian:
                return "sl"
            case .albanian:
                return "sq"
            case .serbian:
                return "sr"
            case .swedish:
                return "sv"
            case .tamil:
                return "ta"
            case .thai:
                return "th"
            case .turkish:
                return "tr"
            case .ukrainian:
                return "uk"
            case .uzbek:
                return "uz"
            case .vietnamese:
                return "vi"
            case .chineseSimplified:
                return "zh-CN"
            case .chineseTraditional:
                return "zh-TW"
        }
    }
}

enum ShortcutStylePreference: CaseIterable, MacroPreference {
    case focusOnRelease
    case doNothingOnRelease

    var localizedString: LocalizedString {
        switch self {
            case .focusOnRelease: return NSLocalizedString("Focus selected window", comment: "")
            case .doNothingOnRelease: return NSLocalizedString("Do nothing", comment: "")
        }
    }
}

enum ShowHowPreference: CaseIterable, MacroPreference {
    case show
    case hide
    case showAtTheEnd

    var localizedString: LocalizedString {
        switch self {
            case .show: return NSLocalizedString("Show", comment: "")
            case .showAtTheEnd: return NSLocalizedString("Show at the end", comment: "")
            case .hide: return NSLocalizedString("Hide", comment: "")
        }
    }
}

enum WindowOrderPreference: CaseIterable, MacroPreference {
    case recentlyFocused
    case recentlyCreated
    case alphabetical
    case space

    var localizedString: LocalizedString {
        switch self {
            case .recentlyFocused: return NSLocalizedString("Recently Focused First", comment: "")
            case .recentlyCreated: return NSLocalizedString("Recently Created First", comment: "")
            case .alphabetical: return NSLocalizedString("Alphabetical Order", comment: "")
            case .space: return NSLocalizedString("Space Order", comment: "")
        }
    }
}

enum AppsToShowPreference: CaseIterable, MacroPreference {
    case all
    case active

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All apps", comment: "")
            case .active: return NSLocalizedString("Active app", comment: "")
        }
    }
}

enum SpacesToShowPreference: CaseIterable, MacroPreference {
    case all
    case visible

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All Spaces", comment: "")
            case .visible: return NSLocalizedString("Visible Spaces", comment: "")
        }
    }
}

enum ScreensToShowPreference: CaseIterable, MacroPreference {
    case all
    case showingAltTab

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All screens", comment: "")
            case .showingAltTab: return NSLocalizedString("Screen showing AltTab", comment: "")
        }
    }
}

enum ShowOnScreenPreference: CaseIterable, MacroPreference {
    case active
    case includingMouse
    case includingMenubar

    var localizedString: LocalizedString {
        switch self {
            case .active: return NSLocalizedString("Active screen", comment: "")
            case .includingMouse: return NSLocalizedString("Screen including mouse", comment: "")
            case .includingMenubar: return NSLocalizedString("Screen including menu bar", comment: "")
        }
    }
}

enum TitleTruncationPreference: CaseIterable, MacroPreference {
    case start
    case middle
    case end

    var localizedString: LocalizedString {
        switch self {
            case .start: return NSLocalizedString("Start", comment: "")
            case .middle: return NSLocalizedString("Middle", comment: "")
            case .end: return NSLocalizedString("End", comment: "")
        }
    }
}

enum ShowAppsOrWindowsPreference: CaseIterable, MacroPreference {
    case applications
    case windows

    var localizedString: LocalizedString {
        switch self {
            case .applications: return NSLocalizedString("Applications", comment: "")
            case .windows: return NSLocalizedString("Windows", comment: "")
        }
    }
}

enum ShowTitlesPreference: CaseIterable, MacroPreference {
    case windowTitle
    case appName
    case appNameAndWindowTitle

    var localizedString: LocalizedString {
        switch self {
            case .windowTitle: return NSLocalizedString("Window Title", comment: "")
            case .appName: return NSLocalizedString("Application Name", comment: "")
            case .appNameAndWindowTitle: return NSLocalizedString("Application Name - Window Title", comment: "")
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .windowTitle: return WidthHeightImage(name: "show_running_windows")
            case .appName: return WidthHeightImage(name: "show_running_applications")
            case .appNameAndWindowTitle: return WidthHeightImage(name: "show_running_applications_windows")
        }
    }
}

enum AlignThumbnailsPreference: CaseIterable, ImageMacroPreference {
    case leading
    case center

    var localizedString: LocalizedString {
        switch self {
            case .leading: return NSLocalizedString("Leading", comment: "")
            case .center: return NSLocalizedString("Center", comment: "")
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .leading: return WidthHeightImage(name: "align_thumbnails_leading")
            case .center: return WidthHeightImage(name: "align_thumbnails_center")
        }
    }
}

enum AppearanceStylePreference: CaseIterable, ImageMacroPreference {
    case thumbnails
    case appIcons
    case titles

    var localizedString: LocalizedString {
        switch self {
            case .thumbnails: return NSLocalizedString("Thumbnails", comment: "")
            case .appIcons: return NSLocalizedString("App Icons", comment: "")
            case .titles: return NSLocalizedString("Titles", comment: "")
        }
    }

    var image: WidthHeightImage {
        let width = CGFloat(150)
        let height = width / 1.6
        switch self {
            case .thumbnails: return WidthHeightImage(width: width, height: height, name: "thumbnails")
            case .appIcons: return WidthHeightImage(width: width, height: height, name: "app_icons")
            case .titles: return WidthHeightImage(width: width, height: height, name: "titles")
        }
    }
}

enum AppearanceSizePreference: CaseIterable, SfSymbolMacroPreference {
    case small
    case medium
    case large

    var localizedString: LocalizedString {
        switch self {
            case .small: return NSLocalizedString("Small", comment: "")
            case .medium: return NSLocalizedString("Medium", comment: "")
            case .large: return NSLocalizedString("Large", comment: "")
        }
    }

    var symbolName: String {
        switch self {
            case .small: return "moonphase.waning.gibbous.inverse"
            case .medium: return "moonphase.last.quarter.inverse"
            case .large: return "moonphase.waning.crescent.inverse"
        }
    }
}

enum ThemePreference: CaseIterable, ImageMacroPreference {
    case macOs
    case windows10

    var localizedString: LocalizedString {
        switch self {
            case .macOs: return " macOS"
            case .windows10: return "❖ Windows 10"
        }
    }

    var image: WidthHeightImage {
        switch self {
            case .macOs: return WidthHeightImage(name: "macos")
            case .windows10: return WidthHeightImage(name: "windows10")
        }
    }

    // periphery:ignore
    var themeParameters: ThemeParameters {
        switch self {
            case .macOs: return ThemeParameters(label: localizedString, cellCornerRadius: 10, windowCornerRadius: 23)
            case .windows10: return ThemeParameters(label: localizedString, cellCornerRadius: 0, windowCornerRadius: 0)
        }
    }
}

enum AppearanceThemePreference: CaseIterable, SfSymbolMacroPreference {
    case light
    case dark
    case system

    var localizedString: LocalizedString {
        switch self {
            case .light: return NSLocalizedString("Light", comment: "")
            case .dark: return NSLocalizedString("Dark", comment: "")
            case .system: return NSLocalizedString("System", comment: "")
        }
    }

    var symbolName: String {
        switch self {
            case .light: return "sun.max"
            case .dark: return "moon.fill"
            case .system: return "laptopcomputer"
        }
    }
}

enum AppearanceVisibilityPreference: CaseIterable, SfSymbolMacroPreference {
    case normal
    case high
    case highest

    var localizedString: LocalizedString {
        switch self {
            case .normal: return NSLocalizedString("Normal", comment: "")
            case .high: return NSLocalizedString("High", comment: "")
            case .highest: return NSLocalizedString("Highest", comment: "")
        }
    }

    var symbolName: String {
        switch self {
            case .normal: return "eye"
            case .high: return "eyeglasses"
            case .highest: return "binoculars.fill"
        }
    }
}

enum UpdatePolicyPreference: CaseIterable, MacroPreference {
    case manual
    case autoCheck
    case autoInstall

    var localizedString: LocalizedString {
        switch self {
            case .manual: return NSLocalizedString("Don’t check for updates periodically", comment: "")
            case .autoCheck: return NSLocalizedString("Check for updates periodically", comment: "")
            case .autoInstall: return NSLocalizedString("Auto-install updates periodically", comment: "")
        }
    }
}

enum CrashPolicyPreference: CaseIterable, MacroPreference {
    case never
    case ask
    case always

    var localizedString: LocalizedString {
        switch self {
            case .never: return NSLocalizedString("Never send crash reports", comment: "")
            case .ask: return NSLocalizedString("Ask whether to send crash reports", comment: "")
            case .always: return NSLocalizedString("Always send crash reports", comment: "")
        }
    }
}

enum BlacklistHidePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenNoOpenWindow = "2"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenNoOpenWindow: return NSLocalizedString("When no open window", comment: "")
        }
    }
}

enum BlacklistIgnorePreference: String/* required for jsonEncode */, CaseIterable, MacroPreference, Codable {
    case none = "0"
    case always = "1"
    case whenFullscreen = "2"

    var localizedString: LocalizedString {
        switch self {
            case .none: return ""
            case .always: return NSLocalizedString("Always", comment: "")
            case .whenFullscreen: return NSLocalizedString("When fullscreen", comment: "")
        }
    }
}

struct BlacklistEntry: Codable {
    var bundleIdentifier: String
    var hide: BlacklistHidePreference
    var ignore: BlacklistIgnorePreference
}

extension UserDefaults {
    static var cache = [String: String]()

    func getFromCacheOrFetchAndCache(_ key: String) -> String {
        if let c = UserDefaults.cache[key] {
            return c
        }
        let v = UserDefaults.standard.string(forKey: key)!
        UserDefaults.cache[key] = v
        return v
    }

    func getThenConvertOrReset<T>(_ key: String, _ getterFn: (String) -> T?) -> T {
        let stringValue = getFromCacheOrFetchAndCache(key)
        if let v = getterFn(stringValue) {
            return v
        }
        removeObject(forKey: key)
        UserDefaults.cache.removeValue(forKey: key)
        let stringValue2 = getFromCacheOrFetchAndCache(key)
        let v = getterFn(stringValue2)!
        return v
    }

    func string(_ key: String) -> String {
        return getFromCacheOrFetchAndCache(key)
    }

    func int(_ key: String) -> Int {
        return getThenConvertOrReset(key, { s in Int(s) })
    }

    func bool(_ key: String) -> Bool {
        return getThenConvertOrReset(key, { s in Bool(s) })
    }

    func double(_ key: String) -> Double {
        return getThenConvertOrReset(key, { s in Double(s) })
    }

    func macroPref<A>(_ key: String, _ macroPreferences: [A]) -> A {
        return getThenConvertOrReset(key, { s in Int(s).flatMap { macroPreferences[safe: $0] } })
    }

    func json<T>(_ key: String, _ type: T.Type) -> T where T: Decodable {
        return getThenConvertOrReset(key, { s in jsonDecode(s, type) })
    }

    private func jsonDecode<T>(_ value: String, _ type: T.Type) -> T? where T: Decodable {
        return value.data(using: .utf8).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
