import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

let defaults = UserDefaults.standard

class Preferences {
    static var defaultsDependingOnScreenRatio_ = defaultsDependingOnScreenRatio()

    // default values
    static var defaultValues: [String: String] = [
        "maxScreenUsage": "80",
        "iconSize": "32",
        "fontHeight": "15",
        "holdShortcut": "⌥",
        "holdShortcut2": "⌥",
        "nextWindowShortcut": "⇥",
        "nextWindowShortcut2": keyAboveTabDependingOnInputSource(),
        "focusWindowShortcut": "↩",
        "previousWindowShortcut": "⇧",
        "cancelShortcut": "⎋",
        "closeWindowShortcut": "W",
        "minDeminWindowShortcut": "M",
        "quitAppShortcut": "Q",
        "hideShowAppShortcut": "H",
        "arrowKeysEnabled": "true",
        "mouseHoverEnabled": "true",
        "showFullscreenWindows": "true",
        "showFullscreenWindows2": "true",
        "showMinimizedWindows": "true",
        "showMinimizedWindows2": "true",
        "showHiddenWindows": "true",
        "showHiddenWindows2": "true",
        "showTabsAsWindows": "false",
        "hideColoredCircles": "false",
        "windowDisplayDelay": "0",
        "theme": "0",
        "showOnScreen": "0",
        "titleTruncation": "0",
        "alignThumbnails": "0",
        "appsToShow": "0",
        "appsToShow2": "1",
        "spacesToShow": "0",
        "spacesToShow2": "0",
        "screensToShow": "0",
        "screensToShow2": "0",
        "fadeOutAnimation": "false",
        "hideSpaceNumberLabels": "false",
        "hideStatusIcons": "false",
        "startAtLogin": "true",
        "hideMenubarIcon": "false",
        "dontShowBlacklist": "",
        "disableShortcutsBlacklist": ["com.realvnc.vncviewer", "com.microsoft.rdc.macos", "com.teamviewer.TeamViewer", "org.virtualbox.app.VirtualBoxVM", "com.parallels.vm", "com.citrix.XenAppViewer"].joined(separator: "\n"),
        "disableShortcutsBlacklistOnlyFullscreen": "true",
        "updatePolicy": "1",
        "crashPolicy": "1",
        "rowsCount": defaultsDependingOnScreenRatio_["rowsCount"]!,
        "minCellsPerRow": defaultsDependingOnScreenRatio_["minCellsPerRow"]!,
        "maxCellsPerRow": defaultsDependingOnScreenRatio_["maxCellsPerRow"]!,
        "shortcutStyle": "0",
    ]

    // constant values
    // not exposed as preferences now but may be in the future, probably through macro preferences
    static var windowMaterial: NSVisualEffectView.Material { .dark }
    static var fontColor: NSColor { .white }
    static var windowPadding: CGFloat { 18 }
    static var interCellPadding: CGFloat { 5 }
    static var intraCellPadding: CGFloat { 5 }
    static var fontIconSize: CGFloat { 20 }

    // persisted values
    static var maxScreenUsage: CGFloat { defaults.cgfloat("maxScreenUsage") / CGFloat(100) }
    static var minCellsPerRow: CGFloat { defaults.cgfloat("minCellsPerRow") }
    static var maxCellsPerRow: CGFloat { defaults.cgfloat("maxCellsPerRow") }
    static var rowsCount: CGFloat { defaults.cgfloat("rowsCount") }
    static var iconSize: CGFloat { defaults.cgfloat("iconSize") }
    static var fontHeight: CGFloat { defaults.cgfloat("fontHeight") }
    static var holdShortcut: String { defaults.string("holdShortcut") }
    static var holdShortcut2: String { defaults.string("holdShortcut2") }
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
    static var showFullscreenWindows: [Bool] { ["showFullscreenWindows", "showFullscreenWindows2"].map { defaults.bool($0) } }
    static var showMinimizedWindows: [Bool] { ["showMinimizedWindows", "showMinimizedWindows2"].map { defaults.bool($0) } }
    static var showHiddenWindows: [Bool] { ["showHiddenWindows", "showHiddenWindows2"].map { defaults.bool($0) } }
    static var showTabsAsWindows: Bool { defaults.bool("showTabsAsWindows") }
    static var hideColoredCircles: Bool { defaults.bool("hideColoredCircles") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(defaults.int("windowDisplayDelay")) }
    static var fadeOutAnimation: Bool { defaults.bool("fadeOutAnimation") }
    static var hideSpaceNumberLabels: Bool { defaults.bool("hideSpaceNumberLabels") }
    static var hideStatusIcons: Bool { defaults.bool("hideStatusIcons") }
    static var startAtLogin: Bool { defaults.bool("startAtLogin") }
    static var hideMenubarIcon: Bool { defaults.bool("hideMenubarIcon") }
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
    static var shortcutStyle: ShortcutStylePreference { defaults.macroPref("shortcutStyle", ShortcutStylePreference.allCases) }

    // derived values
    static var cellBorderWidth: CGFloat { theme.themeParameters.cellBorderWidth }
    static var cellCornerRadius: CGFloat { theme.themeParameters.cellCornerRadius }
    static var windowCornerRadius: CGFloat { theme.themeParameters.windowCornerRadius }
    static var highlightBorderColor: NSColor { theme.themeParameters.highlightBorderColor }
    static var highlightBackgroundColor: NSColor { theme.themeParameters.highlightBackgroundColor }
    static var font: NSFont { NSFont.systemFont(ofSize: fontHeight) }

    static func registerDefaults() {
        defaults.register(defaults: defaultValues)
    }

    static func getString(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    static func set(_ key: String, _ value: Any?) {
        defaults.set(value, forKey: key)
    }

    static var all: [String: Any] { defaults.persistentDomain(forName: NSRunningApplication.current.bundleIdentifier!)! }

    static func migratePreferences() {
        let preferencesVersion = "preferencesVersion"
        if let currentVersion = defaults.string(forKey: preferencesVersion) {
            if currentVersion.compare(App.version, options: .numeric) == .orderedAscending {
                updateToNewPreferences(preferencesVersion)
            }
        } else {
            // first time migrating
            updateToNewPreferences(preferencesVersion)
        }
    }

    private static func updateToNewPreferences(_ preferencesVersion: String) {
        migrateDropdownMenuPreference("theme", [" macOS": "0", "❖ Windows 10": "1"])
        // "Main screen" was renamed to "Active screen"
        migrateDropdownMenuPreference("showOnScreen", ["Main screen": "0", "Active screen": "0", "Screen including mouse": "1"])
        migrateDropdownMenuPreference("alignThumbnails", ["Left": "0", "Center": "1"])
        migrateDropdownMenuPreference("appsToShow", ["All apps": "0", "Active app": "1"])
        migrateDropdownMenuPreference("spacesToShow", ["All spaces": "0", "Active space": "1"])
        migrateDropdownMenuPreference("screensToShow", ["All screens": "0", "Screen showing AltTab": "1"])
        defaults.set(App.version, forKey: preferencesVersion)
    }

    // dropdowns preferences used to store English text; now they store indexes
    static func migrateDropdownMenuPreference(_ preference: String, _ oldAndNew: [String: String]) {
        if let old = defaults.string(forKey: preference),
           let new = oldAndNew[old] {
            defaults.set(new, forKey: preference)
        }
    }

    static func blacklistStringToArray(_ blacklist: String) -> [String] {
        return blacklist.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func defaultsDependingOnScreenRatio() -> [String: String] {
        let ratio = Screen.mainScreenRatio()
        // landscape
        if ratio > 1 {
            // 15/10 and wider; tested with 16/10 and 16/9
            if ratio > (15 / 10) {
                return ["rowsCount": "4", "minCellsPerRow": "4", "maxCellsPerRow": "7"]
            }
            // narrower than 15/10; tested with 4/3
            return ["rowsCount": "3", "minCellsPerRow": "4", "maxCellsPerRow": "7"]
        }
        // vertical; tested with 10/16
        return ["rowsCount": "6", "minCellsPerRow": "3", "maxCellsPerRow": "4"]
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
    case active

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All spaces", comment: "")
            case .active: return NSLocalizedString("Active space", comment: "")
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
    case end
    case middle
    case start

    var localizedString: LocalizedString {
        switch self {
            case .end: return NSLocalizedString("End", comment: "")
            case .middle: return NSLocalizedString("Middle", comment: "")
            case .start: return NSLocalizedString("Start", comment: "")
        }
    }
}

enum AlignThumbnailsPreference: CaseIterable, MacroPreference {
    case left
    case center

    var localizedString: LocalizedString {
        switch self {
            case .left: return NSLocalizedString("Left", comment: "")
            case .center: return NSLocalizedString("Center", comment: "")
        }
    }
}

enum ThemePreference: CaseIterable, MacroPreference {
    case macOs
    case windows10

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

extension UserDefaults {
    func string(_ key: String) -> String {
        string(forKey: key)!
    }

    func int(_ key: String) -> Int {
        if let result = Int(string(key)) {
            return result
        }
        removeObject(forKey: key)
        return int(key)
    }

    func bool(_ key: String) -> Bool {
        if let result = Bool(string(key)) {
            return result
        }
        removeObject(forKey: key)
        return bool(key)
    }

    func cgfloat(_ key: String) -> CGFloat {
        if let result = (NumberFormatter().number(from: string(key)).flatMap { CGFloat(truncating: $0) }) {
            return result
        }
        removeObject(forKey: key)
        return cgfloat(key)
    }

    func macroPref<A>(_ key: String, _ macroPreferences: [A]) -> A {
        let index = int(key)
        if index >= 0 && index < macroPreferences.count {
            return macroPreferences[index]
        }
        removeObject(forKey: key)
        return macroPref(key, macroPreferences)
    }
}
