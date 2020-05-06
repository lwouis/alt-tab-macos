import Cocoa
import Carbon.HIToolbox.Events

let defaults = UserDefaults.standard

class Preferences {
    // default values
    static var defaultValues: [String: String] = [
        "maxScreenUsage": "80",
        "minCellsPerRow": "5",
        "maxCellsPerRow": "10",
        "rowsCount": "3",
        "iconSize": "32",
        "fontHeight": "15",
        "holdShortcut": "⌥",
        "nextWindowShortcut": "⇥",
        "previousWindowShortcut": "⇧⇥",
        "cancelShortcut": "⎋",
        "closeWindowShortcut": "W",
        "minDeminWindowShortcut": "M",
        "quitAppShortcut": "Q",
        "hideShowAppShortcut": "H",
        "arrowKeysEnabled": "true",
        "mouseHoverEnabled": "true",
        "showMinimizedWindows": "true",
        "showHiddenWindows": "true",
        "showTabsAsWindows": "false",
        "windowDisplayDelay": "0",
        "theme": "0",
        "showOnScreen": "0",
        "alignThumbnails": "0",
        "appsToShow": "0",
        "spacesToShow": "0",
        "screensToShow": "0",
        "hideSpaceNumberLabels": "false",
        "startAtLogin": "true",
    ]

    // constant values
    // not exposed as preferences now but may be in the future, probably through macro preferences
    static var windowMaterial: NSVisualEffectView.Material { .dark }
    static var fontColor: NSColor { .white }
    static var windowPadding: CGFloat { 23 }
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
    static var nextWindowShortcut: String { defaults.string("nextWindowShortcut") }
    static var previousWindowShortcut: String { defaults.string("previousWindowShortcut") }
    static var cancelShortcut: String { defaults.string("cancelShortcut") }
    static var closeWindowShortcut: String { defaults.string("closeWindowShortcut") }
    static var minDeminWindowShortcut: String { defaults.string("minDeminWindowShortcut") }
    static var quitAppShortcut: String { defaults.string("quitAppShortcut") }
    static var hideShowAppShortcut: String { defaults.string("hideShowAppShortcut") }
    static var arrowKeysEnabled: Bool { defaults.bool("arrowKeysEnabled") }
    static var mouseHoverEnabled: Bool { defaults.bool("mouseHoverEnabled") }
    static var showMinimizedWindows: Bool { defaults.bool("showMinimizedWindows") }
    static var showHiddenWindows: Bool { defaults.bool("showHiddenWindows") }
    static var showTabsAsWindows: Bool { defaults.bool("showTabsAsWindows") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(defaults.int("windowDisplayDelay")) }
    static var hideSpaceNumberLabels: Bool { defaults.bool("hideSpaceNumberLabels") }
    static var startAtLogin: Bool { defaults.bool("startAtLogin") }

    // macro values
    static var theme: ThemePreference { defaults.macroPref("theme", ThemePreference.allCases) }
    static var showOnScreen: ShowOnScreenPreference { defaults.macroPref("showOnScreen", ShowOnScreenPreference.allCases) }
    static var alignThumbnails: AlignThumbnailsPreference { defaults.macroPref("alignThumbnails", AlignThumbnailsPreference.allCases) }
    static var appsToShow: AppsToShowPreference { defaults.macroPref("appsToShow", AppsToShowPreference.allCases) }
    static var spacesToShow: SpacesToShowPreference { defaults.macroPref("spacesToShow", SpacesToShowPreference.allCases) }
    static var screensToShow: ScreensToShowPreference { defaults.macroPref("screensToShow", ScreensToShowPreference.allCases) }

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

enum AppsToShowPreference: String, CaseIterable, MacroPreference {
    case all = "All apps"
    case active = "Active app"

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All apps", comment: "")
            case .active: return NSLocalizedString("Active app", comment: "")
        }
    }
}

enum SpacesToShowPreference: String, CaseIterable, MacroPreference {
    case all = "All spaces"
    case active = "Active space"

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All spaces", comment: "")
            case .active: return NSLocalizedString("Active space", comment: "")
        }
    }
}

enum ScreensToShowPreference: String, CaseIterable, MacroPreference {
    case all = "All screens"
    case showingAltTab = "Screen showing AltTab"

    var localizedString: LocalizedString {
        switch self {
            case .all: return NSLocalizedString("All screens", comment: "")
            case .showingAltTab: return NSLocalizedString("Screen showing AltTab", comment: "")
        }
    }
}

enum ShowOnScreenPreference: String, CaseIterable, MacroPreference {
    case active = "Active screen"
    case includingMouse = "Screen including mouse"
    case includingMenubar = "Screen including menu bar"

    var localizedString: LocalizedString {
        switch self {
            case .active: return NSLocalizedString("Active screen", comment: "")
            case .includingMouse: return NSLocalizedString("Screen including mouse", comment: "")
            case .includingMenubar: return NSLocalizedString("Screen including menu bar", comment: "")
        }
    }
}

enum AlignThumbnailsPreference: String, CaseIterable, MacroPreference {
    case left = "Left"
    case center = "Center"

    var localizedString: LocalizedString {
        switch self {
            case .left: return NSLocalizedString("Left", comment: "")
            case .center: return NSLocalizedString("Center", comment: "")
        }
    }
}

enum ThemePreference: String, CaseIterable, MacroPreference {
    case macOs = " macOS"
    case windows10 = "❖ Windows 10"

    var localizedString: LocalizedString {
        switch self {
            case .macOs: return NSLocalizedString(" macOS", comment: "")
            case .windows10: return NSLocalizedString("❖ Windows 10", comment: "")
        }
    }

    var themeParameters: ThemeParameters {
        switch self {
            case .macOs: return ThemeParameters(label: self.localizedString, cellBorderWidth: 0, cellCornerRadius: 5, windowCornerRadius: 20, highlightBorderColor: .clear, highlightBackgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            case .windows10: return ThemeParameters(label: self.localizedString, cellBorderWidth: 2, cellCornerRadius: 0, windowCornerRadius: 0, highlightBorderColor: .white, highlightBackgroundColor: .clear)
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
