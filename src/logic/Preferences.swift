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
        "tabKeyCode": kVK_Tab,
        "windowDisplayDelay": 0,
        "metaKey": MacroPreferences.metaKeyList.keys.first!,
        "theme": MacroPreferences.themeList.keys.first!,
        "showOnScreen": MacroPreferences.showOnScreenList.keys.first!,
        "alignThumbnails": MacroPreferences.alignThumbnailsList.keys.first!,
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
    static var tabKeyCode: UInt16 { UInt16(defaults.integer(forKey: "tabKeyCode")) }
    static var windowDisplayDelay: DispatchTimeInterval { DispatchTimeInterval.milliseconds(defaults.integer(forKey: "windowDisplayDelay")) }
    static var hideSpaceNumberLabels: Bool { defaults.bool(forKey: "hideSpaceNumberLabels") }
    static var startAtLogin: Bool { defaults.bool(forKey: "startAtLogin") }

    // macro values
    static var theme: Theme { MacroPreferences.themeList[defaults.string(forKey: "theme")!]! }
    static var metaKey: MetaKey { MacroPreferences.metaKeyList[defaults.string(forKey: "metaKey")!]! }
    static var showOnScreen: ShowOnScreenPreference { MacroPreferences.showOnScreenList[defaults.string(forKey: "showOnScreen")!]! }
    static var alignThumbnails: AlignThumbnailsPreference { MacroPreferences.alignThumbnailsList[defaults.string(forKey: "alignThumbnails")!]! }

    // derived values
    static var cellBorderWidth: CGFloat { theme.cellBorderWidth }
    static var cellCornerRadius: CGFloat { theme.cellCornerRadius }
    static var windowCornerRadius: CGFloat { theme.windowCornerRadius }
    static var highlightBorderColor: NSColor { theme.highlightBorderColor }
    static var highlightBackgroundColor: NSColor { theme.highlightBackgroundColor }
    static var metaKeyCodes: [UInt16] { metaKey.keyCodes.map { UInt16($0) } }
    static var metaModifierFlag: NSEvent.ModifierFlags { metaKey.modifierFlag }
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
}

struct Theme {
    let label: String
    let cellBorderWidth: CGFloat
    let cellCornerRadius: CGFloat
    let windowCornerRadius: CGFloat
    let highlightBorderColor: NSColor
    let highlightBackgroundColor: NSColor
}

struct MetaKey {
    let label: String
    let keyCodes: [Int]
    let modifierFlag: NSEvent.ModifierFlags
}

enum ShowOnScreenPreference {
    case main
    case mouse
}

enum AlignThumbnailsPreference {
    case left
    case center
}

// macros are collection of values derived from a single key
// we don't want to store every value in UserDefaults as the user could change them and contradict the macro
class MacroPreferences {
    static let themeList = [
        " macOS": Theme(label: " macOS", cellBorderWidth: 0, cellCornerRadius: 5, windowCornerRadius: 20, highlightBorderColor: .clear, highlightBackgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.4)),
        "❖ Windows 10": Theme(label: "❖ Windows 10", cellBorderWidth: 2, cellCornerRadius: 0, windowCornerRadius: 0, highlightBorderColor: .white, highlightBackgroundColor: .clear),
    ]
    static let metaKeyList = [
        "⌥ option": MetaKey(label: "⌥ option", keyCodes: [kVK_Option, kVK_RightOption], modifierFlag: .option),
        "⌃ control": MetaKey(label: "⌃ control", keyCodes: [kVK_Control, kVK_RightControl], modifierFlag: .control),
        "⌘ command": MetaKey(label: "⌘ command", keyCodes: [kVK_Command, kVK_RightCommand], modifierFlag: .command)
    ]
    static let showOnScreenList = [
        "Main screen": ShowOnScreenPreference.main,
        "Screen including mouse": ShowOnScreenPreference.mouse,
    ]
    static let alignThumbnailsList = [
        "Center": AlignThumbnailsPreference.center,
        "Left": AlignThumbnailsPreference.left,
    ]
}
