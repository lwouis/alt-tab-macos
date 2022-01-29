import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

let defaults = UserDefaults.standard

class Preferences {
    // default values
    static var defaultValues: [String: String] = [
        "maxWidthOnScreen": "80",
        "maxHeightOnScreen": "80",
        "iconSize": "32",
        "fontHeight": "15",
        "holdShortcut": "⌥",
        "holdShortcut2": "⌥",
        "nextWindowShortcut": "⇥",
        "nextWindowShortcut2": keyAboveTabDependingOnInputSource(),
        "focusWindowShortcut": "Space",
        "previousWindowShortcut": "⇧",
        "cancelShortcut": "⎋",
        "closeWindowShortcut": "W",
        "minDeminWindowShortcut": "M",
        "quitAppShortcut": "Q",
        "hideShowAppShortcut": "H",
        "arrowKeysEnabled": "true",
        "mouseHoverEnabled": "true",
        "cursorFollowFocusEnabled": "false",
        "showMinimizedWindows": ShowHowPreference.show.rawValue,
        "showMinimizedWindows2": ShowHowPreference.show.rawValue,
        "showHiddenWindows": ShowHowPreference.show.rawValue,
        "showHiddenWindows2": ShowHowPreference.show.rawValue,
        "showFullscreenWindows": ShowHowPreference.show.rawValue,
        "showFullscreenWindows2": ShowHowPreference.show.rawValue,
        "showTabsAsWindows": "false",
        "hideColoredCircles": "false",
        "windowDisplayDelay": "0",
        "theme": ThemePreference.macOs.rawValue,
        "showOnScreen": ShowOnScreenPreference.active.rawValue,
        "titleTruncation": TitleTruncationPreference.end.rawValue,
        "alignThumbnails": AlignThumbnailsPreference.left.rawValue,
        "appsToShow": AppsToShowPreference.all.rawValue,
        "appsToShow2": AppsToShowPreference.active.rawValue,
        "spacesToShow": SpacesToShowPreference.all.rawValue,
        "spacesToShow2": SpacesToShowPreference.all.rawValue,
        "screensToShow": ScreensToShowPreference.all.rawValue,
        "screensToShow2": ScreensToShowPreference.all.rawValue,
        "fadeOutAnimation": "false",
        "hideSpaceNumberLabels": "false",
        "hideStatusIcons": "false",
        "startAtLogin": "true",
        "menubarIcon": MenubarIconPreference.outlined.rawValue,
        "dontShowBlacklist": ["com.McAfee.McAfeeSafariHost"].joined(separator: "\n"),
        "disableShortcutsBlacklist": ["com.realvnc.vncviewer", "com.microsoft.rdc.macos", "com.teamviewer.TeamViewer", "org.virtualbox.app.VirtualBoxVM", "com.parallels.", "com.citrix.XenAppViewer", "com.citrix.receiver.icaviewer.mac", "com.nicesoftware.dcvviewer", "com.vmware.fusion", "com.apple.ScreenSharing"].joined(separator: "\n"),
        "disableShortcutsBlacklistOnlyFullscreen": "true",
        "updatePolicy": UpdatePolicyPreference.autoCheck.rawValue,
        "crashPolicy": CrashPolicyPreference.ask.rawValue,
        "rowsCount": rowCountDependingOnScreenRatio(),
        "windowMinWidthInRow": "15",
        "windowMaxWidthInRow": "30",
        "shortcutStyle": ShortcutStylePreference.focusOnRelease.rawValue,
        "shortcutStyle2": ShortcutStylePreference.focusOnRelease.rawValue,
        "hideAppBadges": "false",
        "hideWindowlessApps": "false",
        "hideThumbnails": "false",
    ]

    // constant values
    // not exposed as preferences now but may be in the future, probably through macro preferences
    static var windowMaterial: NSVisualEffectView.Material { .dark }
    static var fontColor: NSColor { .white }
    static var windowPadding: CGFloat { 18 }
    static var interCellPadding: CGFloat { 5 }
    static var intraCellPadding: CGFloat { 5 }

    // persisted values
    static var maxWidthOnScreen: CGFloat { defaults.cgfloat("maxWidthOnScreen") / CGFloat(100) }
    static var maxHeightOnScreen: CGFloat { defaults.cgfloat("maxHeightOnScreen") / CGFloat(100) }
    static var windowMaxWidthInRow: CGFloat { defaults.cgfloat("windowMaxWidthInRow") / CGFloat(100) }
    static var windowMinWidthInRow: CGFloat { defaults.cgfloat("windowMinWidthInRow") / CGFloat(100) }
    static var rowsCount: CGFloat { defaults.cgfloat("rowsCount") }
    static var iconSize: CGFloat { defaults.cgfloat("iconSize") }
    static var fontHeight: CGFloat { defaults.cgfloat("fontHeight") }
    static var holdShortcut: [String] { ["holdShortcut", "holdShortcut2"].map { defaults.string($0) } }
    static var nextWindowShortcut: [String] { ["nextWindowShortcut", "nextWindowShortcut2"].map { defaults.string($0) } }
    static var focusWindowShortcut: String { defaults.string("focusWindowShortcut") }
    static var previousWindowShortcut: String { defaults.string("previousWindowShortcut") }
    static var cancelShortcut: String { defaults.string("cancelShortcut") }
    static var closeWindowShortcut: String { defaults.string("closeWindowShortcut") }
    static var minDeminWindowShortcut: String { defaults.string("minDeminWindowShortcut") }
    static var quitAppShortcut: String { defaults.string("quitAppShortcut") }
    static var hideShowAppShortcut: String { defaults.string("hideShowAppShortcut") }
    static var arrowKeysEnabled: Bool { defaults.bool("arrowKeysEnabled") }
    static var mouseHoverEnabled: Bool { defaults.bool("mouseHoverEnabled") }
    static var cursorFollowFocusEnabled: Bool { defaults.bool("cursorFollowFocusEnabled") }
    static var showTabsAsWindows: Bool { defaults.bool("showTabsAsWindows") }
    static var hideColoredCircles: Bool { defaults.bool("hideColoredCircles") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(defaults.int("windowDisplayDelay")) }
    static var fadeOutAnimation: Bool { defaults.bool("fadeOutAnimation") }
    static var hideSpaceNumberLabels: Bool { defaults.bool("hideSpaceNumberLabels") }
    static var hideStatusIcons: Bool { defaults.bool("hideStatusIcons") }
    static var hideAppBadges: Bool { defaults.bool("hideAppBadges") }
    static var hideWindowlessApps: Bool { defaults.bool("hideWindowlessApps") }
    static var hideThumbnails: Bool { defaults.bool("hideThumbnails") }
    static var startAtLogin: Bool { defaults.bool("startAtLogin") }
    static var dontShowBlacklist: [String] { blacklistStringToArray(defaults.string("dontShowBlacklist")) }
    static var disableShortcutsBlacklist: [String] { blacklistStringToArray(defaults.string("disableShortcutsBlacklist")) }
    static var disableShortcutsBlacklistOnlyFullscreen: Bool { defaults.bool("disableShortcutsBlacklistOnlyFullscreen") }

    // macro values
    static var theme: ThemePreference { defaults.macroPref("theme", ThemePreference.allCases) }
    static var showOnScreen: ShowOnScreenPreference { defaults.macroPref("showOnScreen", ShowOnScreenPreference.allCases) }
    static var titleTruncation: TitleTruncationPreference { defaults.macroPref("titleTruncation", TitleTruncationPreference.allCases) }
    static var alignThumbnails: AlignThumbnailsPreference { defaults.macroPref("alignThumbnails", AlignThumbnailsPreference.allCases) }
    static var updatePolicy: UpdatePolicyPreference { defaults.macroPref("updatePolicy", UpdatePolicyPreference.allCases) }
    static var crashPolicy: CrashPolicyPreference { defaults.macroPref("crashPolicy", CrashPolicyPreference.allCases) }
    static var appsToShow: [AppsToShowPreference] { ["appsToShow", "appsToShow2"].map { defaults.macroPref($0, AppsToShowPreference.allCases) } }
    static var spacesToShow: [SpacesToShowPreference] { ["spacesToShow", "spacesToShow2"].map { defaults.macroPref($0, SpacesToShowPreference.allCases) } }
    static var screensToShow: [ScreensToShowPreference] { ["screensToShow", "screensToShow2"].map { defaults.macroPref($0, ScreensToShowPreference.allCases) } }
    static var showMinimizedWindows: [ShowHowPreference] { ["showMinimizedWindows", "showMinimizedWindows2"].map { defaults.macroPref($0, ShowHowPreference.allCases) } }
    static var showHiddenWindows: [ShowHowPreference] { ["showHiddenWindows", "showHiddenWindows2"].map { defaults.macroPref($0, ShowHowPreference.allCases) } }
    static var showFullscreenWindows: [ShowHowPreference] { ["showFullscreenWindows", "showFullscreenWindows2"].map { defaults.macroPref($0, ShowHowPreference.allCases) } }
    static var shortcutStyle: [ShortcutStylePreference] { ["shortcutStyle", "shortcutStyle2"].map { defaults.macroPref($0, ShortcutStylePreference.allCases) } }
    static var menubarIcon: MenubarIconPreference { defaults.macroPref("menubarIcon", MenubarIconPreference.allCases) }

    // derived values
    static var cellBorderWidth: CGFloat { theme.themeParameters.cellBorderWidth }
    static var cellCornerRadius: CGFloat { theme.themeParameters.cellCornerRadius }
    static var windowCornerRadius: CGFloat { theme.themeParameters.windowCornerRadius }
    static var highlightBorderColor: NSColor { theme.themeParameters.highlightBorderColor }
    static var highlightBackgroundColor: NSColor { theme.themeParameters.highlightBackgroundColor }
    static var font: NSFont { NSFont.systemFont(ofSize: fontHeight) }

    static func initialize() {
        removeCorruptedPreferences()
        migratePreferences()
        registerDefaults()
    }

    static func removeCorruptedPreferences() {
        // from v5.1.0+, there are crash reports of users somehow having their hold shortcuts set to ""
        ["holdShortcut", "holdShortcut2"].forEach {
            if let s = defaults.string(forKey: $0), s == "" {
                defaults.removeObject(forKey: $0)
            }
        }
    }

    static func registerDefaults() {
        defaults.register(defaults: defaultValues)
    }

    static func getString(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    static func set(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
        UserDefaults.cache.removeValue(forKey: key)
    }

    static var all: [String: Any] { defaults.persistentDomain(forName: NSRunningApplication.current.bundleIdentifier!)! }

    static func migratePreferences() {
        let preferencesKey = "preferencesVersion"
        if let diskVersion = defaults.string(forKey: preferencesKey) {
            if diskVersion.compare(App.version, options: .numeric) == .orderedAscending {
                updateToNewPreferences(diskVersion)
            }
        }
        defaults.set(App.version, forKey: preferencesKey)
    }

    private static func updateToNewPreferences(_ currentVersion: String) {
        if currentVersion.compare("6.28.1", options: .numeric) != .orderedDescending {
            migrateMinMaxWindowsWidthInRow()
            if currentVersion.compare("6.27.1", options: .numeric) != .orderedDescending {
                // "Start at login" new implem doesn't use Login Items; we remove the entry from previous versions
                migrateLoginItem()
                if currentVersion.compare("6.23.0", options: .numeric) != .orderedDescending {
                    // "Show windows from:" got the "Active Space" option removed
                    migrateShowWindowsFrom()
                    if currentVersion.compare("6.18.1", options: .numeric) != .orderedDescending {
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

    private static func migrateMinMaxWindowsWidthInRow() {
        ["windowMinWidthInRow", "windowMaxWidthInRow"].forEach {
            if let old = defaults.string(forKey: $0) {
                if old == "0" {
                    defaults.set("1", forKey: $0)
                }
            }
        }
    }

    @available(OSX, deprecated: 10.11)
    private static func migrateLoginItem() {
        do {
            let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
            let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil).takeRetainedValue() as! [LSSharedFileListItem]
            let itemName = Bundle.main.bundleURL.lastPathComponent as CFString
            let itemUrl = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
            loginItemsSnapshot.forEach {
                if (LSSharedFileListItemCopyDisplayName($0)?.takeRetainedValue() == itemName) ||
                       (LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == itemUrl) {
                    LSSharedFileListItemRemove(loginItems, $0)
                }
            }
        } catch {
            // the LSSharedFile API is deprecated, and has a runtime crash on M1 Monterey
            // we catch any exception to void the app crashing
        }
    }

    private static func migrateShowWindowsFrom() {
        ["", "2"].forEach { suffix in
            if let spacesToShow = defaults.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "2" {
                    defaults.set("1", forKey: "screensToShow" + suffix)
                    defaults.set("1", forKey: "spacesToShow" + suffix)
                } else if spacesToShow == "1" {
                    defaults.set("1", forKey: "screensToShow" + suffix)
                }
            }
        }
    }

    private static func migrateNextWindowShortcuts() {
        ["", "2"].forEach { suffix in
            if let oldHoldShortcut = defaults.string(forKey: "holdShortcut" + suffix),
               let oldNextWindowShortcut = defaults.string(forKey: "nextWindowShortcut" + suffix) {
                let nextWindowShortcutCleanedUp = oldHoldShortcut.reduce(oldNextWindowShortcut, { $0.replacingOccurrences(of: String($1), with: "") })
                if oldNextWindowShortcut != nextWindowShortcutCleanedUp {
                    defaults.set(nextWindowShortcutCleanedUp, forKey: "nextWindowShortcut" + suffix)
                }
            }
        }
    }

    private static func migrateMaxSizeOnScreenToWidthAndHeight() {
        if let old = defaults.string(forKey: "maxScreenUsage") {
            defaults.set(old, forKey: "maxWidthOnScreen")
            defaults.set(old, forKey: "maxHeightOnScreen")
        }
    }

    private static func migrateShowWindowsCheckboxToDropdown() {
        ["showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows"]
            .flatMap { [$0, $0 + "2"] }
            .forEach {
                if let old = defaults.string(forKey: $0) {
                    if old == "true" {
                        defaults.set(ShowHowPreference.show.rawValue, forKey: $0)
                    } else if old == "false" {
                        defaults.set(ShowHowPreference.hide.rawValue, forKey: $0)
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
        if let old = defaults.string(forKey: "hideMenubarIcon") {
            if old == "true" {
                defaults.set("3", forKey: "menubarIcon")
            }
        }
    }

    static func migratePreferenceValue(_ preference: String, _ oldAndNew: [String: String]) {
        if let old = defaults.string(forKey: preference),
           let new = oldAndNew[old] {
            defaults.set(new, forKey: preference)
        }
    }

    static func blacklistStringToArray(_ blacklist: String) -> [String] {
        return blacklist.components(separatedBy: "\n").compactMap {
            let line = $0.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                return nil
            }
            return line
        }
    }

    static func rowCountDependingOnScreenRatio() -> String {
        // landscape; tested with 4/3, 16/10, 16/9
        if NSScreen.main!.ratio() > 1 {
            return "4"
        }
        // vertical; tested with 10/16
        return "6"
    }

    static func keyAboveTabDependingOnInputSource() -> String {
        return LiteralKeyCodeTransformer.shared.transformedValue(NSNumber(value: kVK_ANSI_Grave)) ?? "`"
    }
}

// MacroPreference are collection of values derived from a single key
// we don't want to store every value in UserDefaults as the user could change them and contradict the macro
protocol MacroPreference {
    var localizedString: LocalizedString { get }
}

struct ThemeParameters {
    let label: String
    let cellBorderWidth: CGFloat
    let cellCornerRadius: CGFloat
    let windowCornerRadius: CGFloat
    let highlightBorderColor: NSColor
    let highlightBackgroundColor: NSColor
}

typealias LocalizedString = String

enum MenubarIconPreference: String, CaseIterable, MacroPreference {
    case outlined = "0"
    case filled = "1"
    case colored = "2"
    case hidden = "3"

    var localizedString: LocalizedString {
        switch self {
            // these spaces are different from each other; they have to be unique
            case .outlined: return " "
            case .filled: return " "
            case .colored: return " "
            case .hidden: return " "
        }
    }
}

enum ShortcutStylePreference: String, CaseIterable, MacroPreference {
    case focusOnRelease = "0"
    case doNothingOnRelease = "1"

    var localizedString: LocalizedString {
        switch self {
            case .focusOnRelease: return NSLocalizedString("Focus selected window", comment: "")
            case .doNothingOnRelease: return NSLocalizedString("Do nothing", comment: "")
        }
    }
}

enum ShowHowPreference: String, CaseIterable, MacroPreference {
    case show = "0"
    case hide = "1"
    case showAtTheEnd = "2"

    var localizedString: LocalizedString {
        switch self {
            case .show: return NSLocalizedString("Show", comment: "")
            case .showAtTheEnd: return NSLocalizedString("Show at the end", comment: "")
            case .hide: return NSLocalizedString("Hide", comment: "")
        }
    }
}

enum AppsToShowPreference: String, CaseIterable, MacroPreference {
    case all = "0"
    case active = "1"

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All apps", comment: "")
            case .active: return NSLocalizedString("Active app", comment: "")
        }
    }
}

enum SpacesToShowPreference: String, CaseIterable, MacroPreference {
    case all = "0"
    case visible = "2"

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All Spaces", comment: "")
            case .visible: return NSLocalizedString("Visible Spaces", comment: "")
        }
    }
}

enum ScreensToShowPreference: String, CaseIterable, MacroPreference {
    case all = "0"
    case showingAltTab = "1"

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All screens", comment: "")
            case .showingAltTab: return NSLocalizedString("Screen showing AltTab", comment: "")
        }
    }
}

enum ShowOnScreenPreference: String, CaseIterable, MacroPreference {
    case active = "0"
    case includingMouse = "1"
    case includingMenubar = "2"

    var localizedString: LocalizedString {
        switch self {
            case .active: return NSLocalizedString("Active screen", comment: "")
            case .includingMouse: return NSLocalizedString("Screen including mouse", comment: "")
            case .includingMenubar: return NSLocalizedString("Screen including menu bar", comment: "")
        }
    }
}

enum TitleTruncationPreference: String, CaseIterable, MacroPreference {
    case end = "0"
    case middle = "1"
    case start = "2"

    var localizedString: LocalizedString {
        switch self {
            case .end: return NSLocalizedString("End", comment: "")
            case .middle: return NSLocalizedString("Middle", comment: "")
            case .start: return NSLocalizedString("Start", comment: "")
        }
    }
}

enum AlignThumbnailsPreference: String, CaseIterable, MacroPreference {
    case left = "0"
    case center = "1"

    var localizedString: LocalizedString {
        switch self {
            case .left: return NSLocalizedString("Left", comment: "")
            case .center: return NSLocalizedString("Center", comment: "")
        }
    }
}

enum ThemePreference: String, CaseIterable, MacroPreference {
    case macOs = "0"
    case windows10 = "1"

    var localizedString: LocalizedString {
        switch self {
            case .macOs: return " macOS"
            case .windows10: return "❖ Windows 10"
        }
    }

    var themeParameters: ThemeParameters {
        switch self {
            case .macOs: return ThemeParameters(label: localizedString, cellBorderWidth: 0, cellCornerRadius: 10, windowCornerRadius: 23, highlightBorderColor: .clear, highlightBackgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            case .windows10: return ThemeParameters(label: localizedString, cellBorderWidth: 2, cellCornerRadius: 0, windowCornerRadius: 0, highlightBorderColor: .white, highlightBackgroundColor: .clear)
        }
    }
}

enum UpdatePolicyPreference: String, CaseIterable, MacroPreference {
    case manual = "0"
    case autoCheck = "1"
    case autoInstall = "2"

    var localizedString: LocalizedString {
        switch self {
            case .manual: return NSLocalizedString("Don’t check for updates periodically", comment: "")
            case .autoCheck: return NSLocalizedString("Check for updates periodically", comment: "")
            case .autoInstall: return NSLocalizedString("Auto-install updates periodically", comment: "")
        }
    }
}

enum CrashPolicyPreference: String, CaseIterable, MacroPreference {
    case never = "0"
    case ask = "1"
    case always = "2"

    var localizedString: LocalizedString {
        switch self {
            case .never: return NSLocalizedString("Never send crash reports", comment: "")
            case .ask: return NSLocalizedString("Ask whether to send crash reports", comment: "")
            case .always: return NSLocalizedString("Always send crash reports", comment: "")
        }
    }
}

extension UserDefaults {
    static var cache = [String: String]()

    func getFromCacheOrFetchAndCache(_ key: String) -> String {
        if let c = UserDefaults.cache[key] {
            return c
        }
        let v = defaults.string(forKey: key)!
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

    func cgfloat(_ key: String) -> CGFloat {
        return getThenConvertOrReset(key, { s in Int(s).flatMap { CGFloat($0) } })
    }

    func double(_ key: String) -> Double {
        return getThenConvertOrReset(key, { s in Double(s) })
    }

    func macroPref<A>(_ key: String, _ macroPreferences: [A]) -> A {
        return getThenConvertOrReset(key, { s in Int(s).flatMap { macroPreferences[safe: $0] } })
    }
}
