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
        "showWindowlessApps": ShowHowPreference2.showAtTheEnd.indexAsString,
        "showWindowlessApps2": ShowHowPreference2.showAtTheEnd.indexAsString,
        "showWindowlessApps3": ShowHowPreference2.showAtTheEnd.indexAsString,
        "showWindowlessApps4": ShowHowPreference2.showAtTheEnd.indexAsString,
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
        "previewFadeInAnimation": "true",
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
        "hideThumbnails": "false",
        "previewFocusedWindow": "false",
        "screenRecordingPermissionSkipped": "false",
    ]

    // system preferences
    static var finderShowsQuitMenuItem: Bool { UserDefaults(suiteName: "com.apple.Finder")?.bool(forKey: "QuitMenuItem") ?? false }

    // persisted values
    static var holdShortcut: [String] { ["holdShortcut", "holdShortcut2", "holdShortcut3"].map { CachedUserDefaults.string($0) } }
    static var nextWindowShortcut: [String] { ["nextWindowShortcut", "nextWindowShortcut2", "nextWindowShortcut3"].map { CachedUserDefaults.string($0) } }
    static var nextWindowGesture: GesturePreference { CachedUserDefaults.macroPref("nextWindowGesture", GesturePreference.allCases) }
    static var focusWindowShortcut: String { CachedUserDefaults.string("focusWindowShortcut") }
    static var previousWindowShortcut: String { CachedUserDefaults.string("previousWindowShortcut") }
    static var cancelShortcut: String { CachedUserDefaults.string("cancelShortcut") }
    static var closeWindowShortcut: String { CachedUserDefaults.string("closeWindowShortcut") }
    static var minDeminWindowShortcut: String { CachedUserDefaults.string("minDeminWindowShortcut") }
    static var toggleFullscreenWindowShortcut: String { CachedUserDefaults.string("toggleFullscreenWindowShortcut") }
    static var quitAppShortcut: String { CachedUserDefaults.string("quitAppShortcut") }
    static var hideShowAppShortcut: String { CachedUserDefaults.string("hideShowAppShortcut") }
    // periphery:ignore
    static var arrowKeysEnabled: Bool { CachedUserDefaults.bool("arrowKeysEnabled") }
    // periphery:ignore
    static var vimKeysEnabled: Bool { CachedUserDefaults.bool("vimKeysEnabled") }
    static var mouseHoverEnabled: Bool { CachedUserDefaults.bool("mouseHoverEnabled") }
    static var cursorFollowFocusEnabled: Bool { CachedUserDefaults.bool("cursorFollowFocusEnabled") }
    static var showTabsAsWindows: Bool { CachedUserDefaults.bool("showTabsAsWindows") }
    static var hideColoredCircles: Bool { CachedUserDefaults.bool("hideColoredCircles") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(CachedUserDefaults.int("windowDisplayDelay")) }
    static var fadeOutAnimation: Bool { CachedUserDefaults.bool("fadeOutAnimation") }
    static var previewFadeInAnimation: Bool { CachedUserDefaults.bool("previewFadeInAnimation") }
    static var hideSpaceNumberLabels: Bool { CachedUserDefaults.bool("hideSpaceNumberLabels") }
    static var hideStatusIcons: Bool { CachedUserDefaults.bool("hideStatusIcons") }
    static var hideAppBadges: Bool { CachedUserDefaults.bool("hideAppBadges") }
    // periphery:ignore
    static var startAtLogin: Bool { CachedUserDefaults.bool("startAtLogin") }
    static var blacklist: [BlacklistEntry] { CachedUserDefaults.json("blacklist", [BlacklistEntry].self) }
    static var previewFocusedWindow: Bool { CachedUserDefaults.bool("previewFocusedWindow") }
    static var screenRecordingPermissionSkipped: Bool { CachedUserDefaults.bool("screenRecordingPermissionSkipped") }

    // macro values
    static var appearanceStyle: AppearanceStylePreference { CachedUserDefaults.macroPref("appearanceStyle", AppearanceStylePreference.allCases) }
    static var appearanceSize: AppearanceSizePreference { CachedUserDefaults.macroPref("appearanceSize", AppearanceSizePreference.allCases) }
    static var appearanceTheme: AppearanceThemePreference { CachedUserDefaults.macroPref("appearanceTheme", AppearanceThemePreference.allCases) }
    static var appearanceVisibility: AppearanceVisibilityPreference { CachedUserDefaults.macroPref("appearanceVisibility", AppearanceVisibilityPreference.allCases) }
    // periphery:ignore
    static var theme: ThemePreference { ThemePreference.macOs/*CachedUserDefaults.macroPref("theme", ThemePreference.allCases)*/ }
    static var showOnScreen: ShowOnScreenPreference { CachedUserDefaults.macroPref("showOnScreen", ShowOnScreenPreference.allCases) }
    static var titleTruncation: TitleTruncationPreference { CachedUserDefaults.macroPref("titleTruncation", TitleTruncationPreference.allCases) }
    static var alignThumbnails: AlignThumbnailsPreference { CachedUserDefaults.macroPref("alignThumbnails", AlignThumbnailsPreference.allCases) }
    static var showAppsOrWindows: ShowAppsOrWindowsPreference { CachedUserDefaults.macroPref("showAppsOrWindows", ShowAppsOrWindowsPreference.allCases) }
    static var showTitles: ShowTitlesPreference { CachedUserDefaults.macroPref("showTitles", ShowTitlesPreference.allCases) }
    static var updatePolicy: UpdatePolicyPreference { CachedUserDefaults.macroPref("updatePolicy", UpdatePolicyPreference.allCases) }
    static var crashPolicy: CrashPolicyPreference { CachedUserDefaults.macroPref("crashPolicy", CrashPolicyPreference.allCases) }
    static var appsToShow: [AppsToShowPreference] { ["appsToShow", "appsToShow2", "appsToShow3", "appsToShow4"].map { CachedUserDefaults.macroPref($0, AppsToShowPreference.allCases) } }
    static var spacesToShow: [SpacesToShowPreference] { ["spacesToShow", "spacesToShow2", "spacesToShow3", "spacesToShow4"].map { CachedUserDefaults.macroPref($0, SpacesToShowPreference.allCases) } }
    static var screensToShow: [ScreensToShowPreference] { ["screensToShow", "screensToShow2", "screensToShow3", "screensToShow4"].map { CachedUserDefaults.macroPref($0, ScreensToShowPreference.allCases) } }
    static var showMinimizedWindows: [ShowHowPreference] { ["showMinimizedWindows", "showMinimizedWindows2", "showMinimizedWindows3", "showMinimizedWindows4"].map { CachedUserDefaults.macroPref($0, ShowHowPreference.allCases) } }
    static var showHiddenWindows: [ShowHowPreference] { ["showHiddenWindows", "showHiddenWindows2", "showHiddenWindows3", "showHiddenWindows4"].map { CachedUserDefaults.macroPref($0, ShowHowPreference.allCases) } }
    static var showFullscreenWindows: [ShowHowPreference] { ["showFullscreenWindows", "showFullscreenWindows2", "showFullscreenWindows3", "showFullscreenWindows4"].map { CachedUserDefaults.macroPref($0, ShowHowPreference.allCases) } }
    static var showWindowlessApps: [ShowHowPreference2] { ["showWindowlessApps", "showWindowlessApps2", "showWindowlessApps3", "showWindowlessApps4"].map { CachedUserDefaults.macroPref($0, ShowHowPreference2.allCases) } }
    static var windowOrder: [WindowOrderPreference] { ["windowOrder", "windowOrder2", "windowOrder3", "windowOrder4"].map { CachedUserDefaults.macroPref($0, WindowOrderPreference.allCases) } }
    static var shortcutStyle: [ShortcutStylePreference] { ["shortcutStyle", "shortcutStyle2", "shortcutStyle3", "shortcutStyle4"].map { CachedUserDefaults.macroPref($0, ShortcutStylePreference.allCases) } }
    static var menubarIcon: MenubarIconPreference { CachedUserDefaults.macroPref("menubarIcon", MenubarIconPreference.allCases) }
    static var menubarIconShown: Bool { CachedUserDefaults.bool("menubarIconShown") }
    static var language: LanguagePreference { CachedUserDefaults.macroPref("language", LanguagePreference.allCases) }

    static let gestureIndex = 3

    static func initialize() {
        PreferencesMigrations.removeCorruptedPreferences()
        PreferencesMigrations.migratePreferences()
        registerDefaults()
    }

    static func resetAll() {
        UserDefaults.standard.removePersistentDomain(forName: App.bundleIdentifier)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaultValues)
    }

    static func set<T>(_ key: String, _ value: T) where T: Encodable {
        UserDefaults.standard.set(key == "blacklist" ? jsonEncode(value) : value, forKey: key)
        CachedUserDefaults.cache.removeValue(forKey: key)
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        CachedUserDefaults.cache.removeValue(forKey: key)
    }

    static var all: [String: Any] { UserDefaults.standard.persistentDomain(forName: App.bundleIdentifier)! }

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

class CachedUserDefaults {
    static var cache = [String: Any]()

    /// retrieve strings in the globalDomain (e.g. defaults read -g KeyRepeat)
    /// these may be nil since we they don't have default values from AltTab
    static func globalString(_ key: String) -> String? {
        if let cached = CachedUserDefaults.cache[key] {
            return cached as? String
        }
        if let string = UserDefaults.standard.string(forKey: key) {
            CachedUserDefaults.cache[key] = string
        }
        return nil
    }

    static func string(_ key: String) -> String {
        if let cachedFinalValue = CachedUserDefaults.cache[key] {
            return cachedFinalValue as! String
        }
        let finalValue = UserDefaults.standard.string(forKey: key)!
        CachedUserDefaults.cache[key] = finalValue
        return finalValue
    }

    static func int(_ key: String) -> Int {
        return getThenConvertOrReset(key, { s in Int(s) })
    }

    static func bool(_ key: String) -> Bool {
        return getThenConvertOrReset(key, { s in Bool(s) })
    }

    static func double(_ key: String) -> Double {
        return getThenConvertOrReset(key, { s in Double(s) })
    }

    static func macroPref<A>(_ key: String, _ macroPreferences: [A]) -> A {
        return getThenConvertOrReset(key, { s in Int(s).flatMap { macroPreferences[safe: $0] } })
    }

    /// some UI elements (e.g. dropdown, radios) need an int. We find the right int from the MacroPreference index
    static func intFromMacroPref(_ key: String, _ macroPreferences: [MacroPreference]) -> Int {
        let macroPref = macroPref(key, macroPreferences)
        return macroPreferences.firstIndex { $0.localizedString == macroPref.localizedString }!
    }

    static func json<T>(_ key: String, _ type: T.Type) -> T where T: Decodable {
        return getThenConvertOrReset(key, { s in jsonDecode(s, type) })
    }

    private static func getThenConvertOrReset<T>(_ key: String, _ getterFn: (String) -> T?) -> T {
        if let cachedFinalValue = CachedUserDefaults.cache[key] {
            return cachedFinalValue as! T
        }
        let stringValue = UserDefaults.standard.string(forKey: key)!
        if let finalValue = getterFn(stringValue) {
            CachedUserDefaults.cache[key] = finalValue
            return finalValue
        }
        // value couldn't be read properly; we remove it and work with the default
        UserDefaults.standard.removeObject(forKey: key)
        let defaultStringValue = UserDefaults.standard.string(forKey: key)!
        let defaultFinalValue = getterFn(defaultStringValue)!
        CachedUserDefaults.cache[key] = defaultFinalValue
        return defaultFinalValue
    }

    private static func jsonDecode<T>(_ value: String, _ type: T.Type) -> T? where T: Decodable {
        return value.data(using: .utf8).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}

struct BlacklistEntry: Codable {
    var bundleIdentifier: String
    var hide: BlacklistHidePreference
    var ignore: BlacklistIgnorePreference
}
