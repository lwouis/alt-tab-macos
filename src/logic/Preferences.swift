import Cocoa
import Carbon.HIToolbox.Events

let defaults = UserDefaults.standard

class Preferences {
    // default values
    static var defaultValues: [String: Any] = [
        "maxScreenUsage": Float(80),
        "minCellsPerRow": Float(5),
        "maxCellsPerRow": Float(10),
        "rowsCount": Float(3),
        "iconSize": Float(32),
        "fontHeight": Float(15),
        "holdShortcut": "⌥",
        "nextWindowShortcut": "⇥",
        "previousWindowShortcut": "⇧⇥",
        "cancelShortcut": "⎋",
        "arrowKeysEnabled": true,
        "mouseHoverEnabled": true,
        "showMinimizedWindows": true,
        "showHiddenWindows": true,
        "windowDisplayDelay": 0,
        "theme": ThemePreference.macOs.rawValue,
        "showOnScreen": ShowOnScreenPreference.active.rawValue,
        "alignThumbnails": AlignThumbnailsPreference.left.rawValue,
        "appsToShow": AppsToShowPreference.all.rawValue,
        "spacesToShow": SpacesToShowPreference.all.rawValue,
        "screensToShow": ScreensToShowPreference.all.rawValue,
        "hideSpaceNumberLabels": false,
        "startAtLogin": true,
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
    static var maxScreenUsage: CGFloat { CGFloat(defaults.float(forKey: "maxScreenUsage") / 100) }
    static var minCellsPerRow: CGFloat { CGFloat(defaults.float(forKey: "minCellsPerRow")) }
    static var maxCellsPerRow: CGFloat { CGFloat(defaults.float(forKey: "maxCellsPerRow")) }
    static var rowsCount: CGFloat { CGFloat(defaults.float(forKey: "rowsCount")) }
    static var iconSize: CGFloat { CGFloat(defaults.float(forKey: "iconSize")) }
    static var fontHeight: CGFloat { CGFloat(defaults.float(forKey: "fontHeight")) }
    static var holdShortcut: String { defaults.string(forKey: "holdShortcut")! }
    static var nextWindowShortcut: String { defaults.string(forKey: "nextWindowShortcut")! }
    static var previousWindowShortcut: String { defaults.string(forKey: "previousWindowShortcut")! }
    static var cancelShortcut: String { defaults.string(forKey: "cancelShortcut")! }
    static var arrowKeysEnabled: Bool { defaults.bool(forKey: "arrowKeysEnabled") }
    static var mouseHoverEnabled: Bool { defaults.bool(forKey: "mouseHoverEnabled") }
    static var showMinimizedWindows: Bool { defaults.bool(forKey: "showMinimizedWindows") }
    static var showHiddenWindows: Bool { defaults.bool(forKey: "showHiddenWindows") }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(defaults.integer(forKey: "windowDisplayDelay")) }
    static var hideSpaceNumberLabels: Bool { defaults.bool(forKey: "hideSpaceNumberLabels") }
    static var startAtLogin: Bool { defaults.bool(forKey: "startAtLogin") }

    // macro values
    static var theme: ThemePreference { ThemePreference(rawValue: defaults.string(forKey: "theme")!)! }
    static var showOnScreen: ShowOnScreenPreference { ShowOnScreenPreference(rawValue: defaults.string(forKey: "showOnScreen")!)! }
    static var alignThumbnails: AlignThumbnailsPreference { AlignThumbnailsPreference(rawValue: defaults.string(forKey: "alignThumbnails")!)! }
    static var appsToShow: AppsToShowPreference { AppsToShowPreference(rawValue: defaults.string(forKey: "appsToShow")!)! }
    static var spacesToShow: SpacesToShowPreference { SpacesToShowPreference(rawValue: defaults.string(forKey: "spacesToShow")!)! }
    static var screensToShow: ScreensToShowPreference { ScreensToShowPreference(rawValue: defaults.string(forKey: "screensToShow")!)! }

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

    static func getObject(_ key: String) -> Any? {
        defaults.object(forKey: key)
    }

    static func getString(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    static func getAsString(_ key: String) -> String {
        String(describing: defaults.object(forKey: key))
    }

    static func set(_ key: String, _ value: Any?) {
        defaults.set(value, forKey: key)
    }

    static var all: [String: Any] { defaults.persistentDomain(forName: NSRunningApplication.current.bundleIdentifier!)! }

    static func migrateOldPreferences() {
        // "Main screen" was renamed to "Active screen"
        if defaults.string(forKey: "showOnScreen") == "Main screen" {
            defaults.removeObject(forKey: "showOnScreen")
        }
    }
}

// MacroPreference are collection of values derived from a single key
// we don't want to store every value in UserDefaults as the user could change them and contradict the macro
protocol MacroPreference {
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

    var localizedString: LocalizedString {
        switch self {
            case .active: return NSLocalizedString("Active screen", comment: "")
            case .includingMouse: return NSLocalizedString("Screen including mouse", comment: "")
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

    var themeParameters: ThemeParameters {
        switch self {
            case .macOs: return ThemeParameters(label: NSLocalizedString(" macOS", comment: ""), cellBorderWidth: 0, cellCornerRadius: 5, windowCornerRadius: 20, highlightBorderColor: .clear, highlightBackgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.4))
            case .windows10: return ThemeParameters(label: NSLocalizedString("❖ Windows 10", comment: ""), cellBorderWidth: 2, cellCornerRadius: 0, windowCornerRadius: 0, highlightBorderColor: .white, highlightBackgroundColor: .clear)
        }
    }
}
