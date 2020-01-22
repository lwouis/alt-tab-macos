import Foundation
import Cocoa
import Carbon.HIToolbox.Events

class Preferences {
    // the following constant are not exposed as preferences but may be in the future, probably through macro preferences
    static let windowMaterial = NSVisualEffectView.Material.dark
    static let iconSize = CGFloat(32)
    static let fontColor = NSColor.white
    static let fontHeight = CGFloat(15)
    static let font = NSFont.systemFont(ofSize: fontHeight)
    static let windowPadding = CGFloat(23)
    static let cellPadding = CGFloat(5)
    static let fontIconSize = CGFloat(20)
    static let maxScreenUsage = CGFloat(0.8)
    static let minCellsPerRow = CGFloat(4)
    static let maxCellsPerRow = CGFloat(6)
    static let nCellsRows = CGFloat(4)

    static let themeMacro = MacroPreferenceHelper<(CGFloat, CGFloat, CGFloat, NSColor, NSColor)>([
        MacroPreference(" macOS", (0, 5, 20, .clear, NSColor(red: 0, green: 0, blue: 0, alpha: 0.3))),
        MacroPreference("❖ Windows 10", (2, 0, 0, .white, .clear))
    ])
    static let metaKeyMacro = MacroPreferenceHelper<([Int], NSEvent.ModifierFlags)>([
        MacroPreference("⌥ option", ([kVK_Option, kVK_RightOption], .option)),
        MacroPreference("⌃ control", ([kVK_Control, kVK_RightControl], .control)),
        MacroPreference("⌘ command", ([kVK_Command, kVK_RightCommand], .command))
    ])
    static let showOnScreenMacro = MacroPreferenceHelper<ShowOnScreenPreference>([
        MacroPreference("Main screen", ShowOnScreenPreference.MAIN),
        MacroPreference("Screen including mouse", ShowOnScreenPreference.MOUSE),
    ])

    static var defaults: [String: String] = [
        "tabKeyCode": String(kVK_Tab),
        "metaKey": metaKeyMacro.macros[0].label,
        "windowDisplayDelay": "0",
        "theme": themeMacro.macros[0].label,
        "showOnScreen": showOnScreenMacro.macros[0].label,
        "hideSpaceNumberLabels": String(false)
    ]
    static var rawValues = [String: String]()

    static var cellBorderWidth: CGFloat?
    static var cellCornerRadius: CGFloat?
    static var tabKeyCode: UInt16?
    static var highlightBorderColor: NSColor?
    static var highlightBackgroundColor: NSColor?
    static var metaKeyCodes: [UInt16]?
    static var metaModifierFlag: NSEvent.ModifierFlags?
    static var windowDisplayDelay: DispatchTimeInterval?
    static var windowCornerRadius: CGFloat?
    static var showOnScreen: ShowOnScreenPreference?
    static var hideSpaceNumberLabels: Bool?

    private static let defaultsFile = fileFromPreferencesFolder("alt-tab-macos-defaults.json")
    private static let userFile = fileFromPreferencesFolder("alt-tab-macos.json")

    static func loadFromDiskAndUpdateValues() {
        do {
            try saveDefaultsToDisk()
            let preferencesExist = FileManager.default.fileExists(atPath: userFile.path)
            if !preferencesExist {
                try FileManager.default.copyItem(at: defaultsFile, to: userFile)
            }
            rawValues = try loadFromDisk(userFile)
            if preferencesExist {
                let compatiblePreferences = rawValues.filter { defaults[$0.key] != nil }
                rawValues = defaults.merging(compatiblePreferences) { (_, new) in new }
            }
            try rawValues.forEach { try updateAndValidateFromString($0.key, $0.value) }
            if preferencesExist {
                try saveRawToDisk()
            }
        } catch {
            debugPrint("Error loading preferences", error)
            if (FileManager.default.fileExists(atPath: userFile.path)) {
                try! FileManager.default.removeItem(at: userFile)
            }
            loadFromDiskAndUpdateValues()
        }
    }

    static func updateAndValidateFromString(_ valueName: String, _ value: String) throws {
        switch valueName {
        case "tabKeyCode":
            tabKeyCode = try UInt16(value).orThrow()
        case "metaKey":
            let p = try metaKeyMacro.labelToMacro[value].orThrow()
            metaKeyCodes = p.preferences.0.map { UInt16($0) }
            metaModifierFlag = p.preferences.1
        case "theme":
            let p = try themeMacro.labelToMacro[value].orThrow()
            cellBorderWidth = p.preferences.0
            cellCornerRadius = p.preferences.1
            windowCornerRadius = p.preferences.2
            highlightBorderColor = p.preferences.3
            highlightBackgroundColor = p.preferences.4
        case "windowDisplayDelay":
            windowDisplayDelay = DispatchTimeInterval.milliseconds(try Int(value).orThrow())
        case "showOnScreen":
            let p = try showOnScreenMacro.labelToMacro[value].orThrow()
            showOnScreen = p.preferences
        case "hideSpaceNumberLabels":
            hideSpaceNumberLabels = try Bool(value).orThrow()
        default:
            throw NSError.make(domain: "Preferences", message: "Tried to update an unknown preference: '\(valueName)' = '\(value)'")
        }
        rawValues[valueName] = value
    }

    static func saveRawToDisk() throws {
        try saveToDisk(rawValues, userFile)
    }

    private static func preferencesVersion(_ url: URL) throws -> Int {
        return try Int(loadFromDisk(url)["version"] ?? "0").orThrow()
    }

    private static func loadFromDisk(_ url: URL) throws -> [String: String] {
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private static func saveDefaultsToDisk() throws {
        try saveToDisk(defaults, defaultsFile)
    }

    private static func saveToDisk(_ values: [String: String], _ path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder
                .encode(values)
                .write(to: path)
    }

    private static func fileFromPreferencesFolder(_ fileName: String) -> URL {
        return FileManager.default
                .urls(for: .libraryDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent(fileName)
    }
}

struct MacroPreference<T> {
    let label: String
    let preferences: T

    init(_ label: String, _ preferences: T) {
        self.label = label
        self.preferences = preferences
    }
}

class MacroPreferenceHelper<T> {
    let macros: [MacroPreference<T>]
    var labels = [String]()
    var labelToMacro = [String: MacroPreference<T>]()

    init(_ array: [MacroPreference<T>]) {
        self.macros = array
        array.forEach {
            labelToMacro[$0.label] = $0
            labels.append($0.label)
        }
    }
}

enum ShowOnScreenPreference {
    case MAIN
    case MOUSE
}
