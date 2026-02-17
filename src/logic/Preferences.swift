import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class Preferences {
    // default values
    static var defaultValues: [String: String] = {
        var values: [String: String] = [
        "shortcutCount": "2",
        "holdShortcut": "⌥",
        "holdShortcut2": "⌥",
        "nextWindowShortcut": "⇥",
        "nextWindowShortcut2": keyAboveTabDependingOnInputSource(),
        "nextWindowGesture": GesturePreference.disabled.indexAsString,
        "focusWindowShortcut": returnKeyEquivalent(),
        "previousWindowShortcut": "⇧",
        "cancelShortcut": "⎋",
        "lockSearchShortcut": "Space",
        "closeWindowShortcut": "W",
        "minDeminWindowShortcut": "M",
        "toggleFullscreenWindowShortcut": "F",
        "quitAppShortcut": "Q",
        "hideShowAppShortcut": "H",
        "searchShortcut": "S",
        "arrowKeysEnabled": "true",
        "vimKeysEnabled": "false",
        "mouseHoverEnabled": "false",
        "cursorFollowFocus": CursorFollowFocus.never.indexAsString,
        "showMinimizedWindows": ShowHowPreference.show.indexAsString,
        "showMinimizedWindows2": ShowHowPreference.show.indexAsString,
        "showHiddenWindows": ShowHowPreference.show.indexAsString,
        "showHiddenWindows2": ShowHowPreference.show.indexAsString,
        "showFullscreenWindows": ShowHowPreference.show.indexAsString,
        "showFullscreenWindows2": ShowHowPreference.show.indexAsString,
        "showWindowlessApps": ShowHowPreference.showAtTheEnd.indexAsString,
        "showWindowlessApps2": ShowHowPreference.showAtTheEnd.indexAsString,
        "windowOrder": WindowOrderPreference.recentlyFocused.indexAsString,
        "windowOrder2": WindowOrderPreference.recentlyFocused.indexAsString,
        "showTabsAsWindows": "false",
        "hideColoredCircles": "false",
        "windowDisplayDelay": "100",
        "appearanceStyle": AppearanceStylePreference.thumbnails.indexAsString,
        "appearanceSize": AppearanceSizePreference.auto.indexAsString,
        "appearanceTheme": AppearanceThemePreference.system.indexAsString,
        "theme": ThemePreference.macOs.indexAsString,
        "showOnScreen": ShowOnScreenPreference.active.indexAsString,
        "titleTruncation": TitleTruncationPreference.end.indexAsString,
        "alignThumbnails": AlignThumbnailsPreference.center.indexAsString,
        "showAppsOrWindows": ShowAppsOrWindowsPreference.windows.indexAsString,
        "showTitles": ShowTitlesPreference.windowTitle.indexAsString,
        "appsToShow": AppsToShowPreference.all.indexAsString,
        "appsToShow2": AppsToShowPreference.active.indexAsString,
        "spacesToShow": SpacesToShowPreference.all.indexAsString,
        "spacesToShow2": SpacesToShowPreference.all.indexAsString,
        "screensToShow": ScreensToShowPreference.all.indexAsString,
        "screensToShow2": ScreensToShowPreference.all.indexAsString,
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
        "hideAppBadges": "false",
        "hideThumbnails": "false",
        "previewFocusedWindow": "false",
        "screenRecordingPermissionSkipped": "false",
        "trackpadHapticFeedbackEnabled": "true",
        "settingsWindowShownOnFirstLaunch": "false",
        ]
        (0..<maxShortcutCount).forEach { index in
            values[indexToName("holdShortcut", index)] = "⌥"
            values[indexToName("nextWindowShortcut", index)] = index == 0 ? "⇥" : (index == 1 ? keyAboveTabDependingOnInputSource() : "")
        }
        (0...maxShortcutCount).forEach { index in
            values[indexToName("appsToShow", index)] = index == 1 ? AppsToShowPreference.active.indexAsString : (index == 2 ? AppsToShowPreference.nonActive.indexAsString : AppsToShowPreference.all.indexAsString)
            values[indexToName("spacesToShow", index)] = SpacesToShowPreference.all.indexAsString
            values[indexToName("screensToShow", index)] = ScreensToShowPreference.all.indexAsString
            values[indexToName("showMinimizedWindows", index)] = ShowHowPreference.show.indexAsString
            values[indexToName("showHiddenWindows", index)] = ShowHowPreference.show.indexAsString
            values[indexToName("showFullscreenWindows", index)] = ShowHowPreference.show.indexAsString
            values[indexToName("showWindowlessApps", index)] = ShowHowPreference.showAtTheEnd.indexAsString
            values[indexToName("windowOrder", index)] = WindowOrderPreference.recentlyFocused.indexAsString
            values[indexToName("shortcutStyle", index)] = ShortcutStylePreference.focusOnRelease.indexAsString
        }
        return values
    }()

    // system preferences
    static var finderShowsQuitMenuItem: Bool { UserDefaults(suiteName: "com.apple.Finder")?.bool(forKey: "QuitMenuItem") ?? false }

    // persisted values
    static var holdShortcut: [String] { (0..<shortcutCount).map { CachedUserDefaults.string(indexToName("holdShortcut", $0)) } }
    static var nextWindowShortcut: [String] { (0..<shortcutCount).map { CachedUserDefaults.string(indexToName("nextWindowShortcut", $0)) } }
    static var nextWindowGesture: GesturePreference { CachedUserDefaults.macroPref("nextWindowGesture", GesturePreference.allCases) }
    static var focusWindowShortcut: String { CachedUserDefaults.string("focusWindowShortcut") }
    static var previousWindowShortcut: String { CachedUserDefaults.string("previousWindowShortcut") }
    static var cancelShortcut: String { CachedUserDefaults.string("cancelShortcut") }
    static var lockSearchShortcut: String { CachedUserDefaults.string("lockSearchShortcut") }
    static var closeWindowShortcut: String { CachedUserDefaults.string("closeWindowShortcut") }
    static var minDeminWindowShortcut: String { CachedUserDefaults.string("minDeminWindowShortcut") }
    static var toggleFullscreenWindowShortcut: String { CachedUserDefaults.string("toggleFullscreenWindowShortcut") }
    static var quitAppShortcut: String { CachedUserDefaults.string("quitAppShortcut") }
    static var hideShowAppShortcut: String { CachedUserDefaults.string("hideShowAppShortcut") }
    static var searchShortcut: String { CachedUserDefaults.string("searchShortcut") }
    // periphery:ignore
    static var arrowKeysEnabled: Bool { CachedUserDefaults.bool("arrowKeysEnabled") }
    // periphery:ignore
    static var vimKeysEnabled: Bool { CachedUserDefaults.bool("vimKeysEnabled") }
    static var mouseHoverEnabled: Bool { CachedUserDefaults.bool("mouseHoverEnabled") }
    static var cursorFollowFocus: CursorFollowFocus { CachedUserDefaults.macroPref("cursorFollowFocus", CursorFollowFocus.allCases) }
    static var trackpadHapticFeedbackEnabled: Bool { CachedUserDefaults.bool("trackpadHapticFeedbackEnabled") }
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
    static var previewSelectedWindow: Bool { CachedUserDefaults.bool("previewFocusedWindow") }
    static var screenRecordingPermissionSkipped: Bool { CachedUserDefaults.bool("screenRecordingPermissionSkipped") }
    static var settingsWindowShownOnFirstLaunch: Bool { CachedUserDefaults.bool("settingsWindowShownOnFirstLaunch") }

    // macro values
    static var appearanceStyle: AppearanceStylePreference { CachedUserDefaults.macroPref("appearanceStyle", AppearanceStylePreference.allCases) }
    static var appearanceSize: AppearanceSizePreference { CachedUserDefaults.macroPref("appearanceSize", AppearanceSizePreference.allCases) }
    static var appearanceTheme: AppearanceThemePreference { CachedUserDefaults.macroPref("appearanceTheme", AppearanceThemePreference.allCases) }
    // periphery:ignore
    static var theme: ThemePreference { ThemePreference.macOs/*CachedUserDefaults.macroPref("theme", ThemePreference.allCases)*/ }
    static var showOnScreen: ShowOnScreenPreference { CachedUserDefaults.macroPref("showOnScreen", ShowOnScreenPreference.allCases) }
    static var titleTruncation: TitleTruncationPreference { CachedUserDefaults.macroPref("titleTruncation", TitleTruncationPreference.allCases) }
    static var alignThumbnails: AlignThumbnailsPreference { CachedUserDefaults.macroPref("alignThumbnails", AlignThumbnailsPreference.allCases) }
    static var showAppsOrWindows: ShowAppsOrWindowsPreference { CachedUserDefaults.macroPref("showAppsOrWindows", ShowAppsOrWindowsPreference.allCases) }
    static var showTitles: ShowTitlesPreference { CachedUserDefaults.macroPref("showTitles", ShowTitlesPreference.allCases) }
    static var updatePolicy: UpdatePolicyPreference { CachedUserDefaults.macroPref("updatePolicy", UpdatePolicyPreference.allCases) }
    static var crashPolicy: CrashPolicyPreference { CachedUserDefaults.macroPref("crashPolicy", CrashPolicyPreference.allCases) }
    static var appsToShow: [AppsToShowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("appsToShow", $0), AppsToShowPreference.allCases) } }
    static var spacesToShow: [SpacesToShowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("spacesToShow", $0), SpacesToShowPreference.allCases) } }
    static var screensToShow: [ScreensToShowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("screensToShow", $0), ScreensToShowPreference.allCases) } }
    static var showMinimizedWindows: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showMinimizedWindows", $0), ShowHowPreference.allCases) } }
    static var showHiddenWindows: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showHiddenWindows", $0), ShowHowPreference.allCases) } }
    static var showFullscreenWindows: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showFullscreenWindows", $0), ShowHowPreference.allCases) } }
    static var showWindowlessApps: [ShowHowPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("showWindowlessApps", $0), ShowHowPreference.allCases) } }
    static var windowOrder: [WindowOrderPreference] { (0...maxShortcutCount).map { CachedUserDefaults.macroPref(indexToName("windowOrder", $0), WindowOrderPreference.allCases) } }
    static var shortcutStyle: ShortcutStylePreference { CachedUserDefaults.macroPref("shortcutStyle", ShortcutStylePreference.allCases) }
    static var menubarIcon: MenubarIconPreference { CachedUserDefaults.macroPref("menubarIcon", MenubarIconPreference.allCases) }
    static var menubarIconShown: Bool { CachedUserDefaults.bool("menubarIconShown") }
    static var language: LanguagePreference { CachedUserDefaults.macroPref("language", LanguagePreference.allCases) }

    static let minShortcutCount = 1
    static let maxShortcutCount = 9
    static var shortcutCount: Int {
        max(minShortcutCount, min(maxShortcutCount, CachedUserDefaults.int("shortcutCount")))
    }

    static let gestureIndex = maxShortcutCount

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

    static func markSettingsWindowShownOnFirstLaunch() {
        set("settingsWindowShownOnFirstLaunch", "true", false)
    }

    static func set<T>(_ key: String, _ value: T, _ notify: Bool = true) where T: Encodable {
        UserDefaults.standard.set(key == "blacklist" ? jsonEncode(value) : value, forKey: key)
        CachedUserDefaults.removeFromCache(key)
        if notify {
            PreferencesEvents.preferenceChanged(key)
        }
    }

    static func remove(_ key: String, _ notify: Bool = true) {
        UserDefaults.standard.removeObject(forKey: key)
        CachedUserDefaults.removeFromCache(key)
        if notify {
            PreferencesEvents.preferenceChanged(key)
        }
    }

    static var all: [String: Any] { UserDefaults.standard.persistentDomain(forName: App.bundleIdentifier)! }

    static func onlyShowApplications() -> Bool {
        return Preferences.showAppsOrWindows == .applications && Preferences.appearanceStyle != .thumbnails
    }

    /// key-above-tab is ` on US keyboard, but can be different on other keyboards
    static func keyAboveTabDependingOnInputSource() -> String {
        return LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: kVK_ANSI_Grave)) ?? "`"
    }

    static func returnKeyEquivalent() -> String {
        return LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: kVK_Return)) ?? "↩"
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
        let digits = String(name.reversed().prefix { $0.isNumber }.reversed())
        guard !digits.isEmpty, let number = Int(digits) else { return 0 }
        return number - 1
    }
}

class CachedUserDefaults {
    static var cache = AXUIElement.ConcurrentMap<String, Any>()

    static func removeFromCache(_ key: String) {
        cache.withLock { $0.removeValue(forKey: key) }
    }

    /// retrieve strings in the globalDomain (e.g. defaults read -g KeyRepeat)
    /// these may be nil since we they don't have default values from AltTab
    static func globalString(_ key: String) -> String? {
        if let cached = cache.withLock({ $0[key] }) {
            return cached as? String
        }
        if let string = UserDefaults.standard.string(forKey: key) {
            cache.withLock { $0[key] = string }
        }
        return nil
    }

    static func string(_ key: String) -> String {
        if let cachedFinalValue = cache.withLock({ $0[key] }) {
            return cachedFinalValue as! String
        }
        let finalValue = UserDefaults.standard.string(forKey: key)!
        cache.withLock { $0[key] = finalValue }
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
        if let cachedFinalValue = cache.withLock({ $0[key] }) {
            return cachedFinalValue as! T
        }
        let stringValue = UserDefaults.standard.string(forKey: key)!
        if let finalValue = getterFn(stringValue) {
            cache.withLock { $0[key] = finalValue }
            return finalValue
        }
        // value couldn't be read properly; we remove it and work with the default
        UserDefaults.standard.removeObject(forKey: key)
        let defaultStringValue = UserDefaults.standard.string(forKey: key)!
        let defaultFinalValue = getterFn(defaultStringValue)!
        cache.withLock { $0[key] = defaultFinalValue }
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
