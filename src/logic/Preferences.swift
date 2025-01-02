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

/// workaround to silence compiler warning
private protocol AvoidDeprecationWarnings {
    static func migrateLoginItem()
}
extension Preferences: AvoidDeprecationWarnings {
}

struct BlacklistEntry: Codable {
    var bundleIdentifier: String
    var hide: BlacklistHidePreference
    var ignore: BlacklistIgnorePreference
}
