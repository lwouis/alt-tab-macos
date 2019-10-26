import Foundation
import Cocoa

class Preferences {
    static var defaults: [String: String] = [
        "version": "2", // bump this anytime the dictionary is changed
        "maxScreenUsage": "80",
        "maxThumbnailsPerRow": "4",
        "iconSize": "32",
        "fontHeight": "15",
        "tabKeyCode": String(KeyCode.tab.rawValue),
        "metaKey": metaKeyMacro.macros[0].label,
        "windowDisplayDelay": "0",
        "theme": themeMacro.macros[0].label
    ]
    static var rawValues = [String: String]()
    static var thumbnailMaxWidth: CGFloat = 200
    static var thumbnailMaxHeight: CGFloat = 200
    static var minimumWindowSize: CGFloat = 200
    static var fontColor: NSColor = .white
    static var windowMaterial: NSVisualEffectView.Material = .dark
    static var windowPadding: CGFloat = 23
    static var interItemPadding: CGFloat = 4
    static var cellPadding: CGFloat = 6
    static var cellBorderWidth: CGFloat?
    static var cellCornerRadius: CGFloat?
    static var maxScreenUsage: CGFloat?
    static var maxThumbnailsPerRow: CGFloat?
    static var iconSize: CGFloat?
    static var fontHeight: CGFloat?
    static var tabKeyCode: UInt16?
    static var highlightBorderColor: NSColor?
    static var highlightBackgroundColor: NSColor?
    static var metaKeyCode: KeyCode?
    static var metaModifierFlag: NSEvent.ModifierFlags?
    static var windowDisplayDelay: DispatchTimeInterval?
    static var windowCornerRadius: CGFloat?
    static var font: NSFont?
    static var themeMacro = MacroPreferenceHelper<(CGFloat, CGFloat, CGFloat, NSColor, NSColor)>([
        MacroPreference(" macOS", (0, 5, 20, .clear, NSColor(red: 0, green: 0, blue: 0, alpha: 0.3))),
        MacroPreference("❖ Windows 10", (2, 0, 0, .white, .clear))
    ])
    static var metaKeyMacro = MacroPreferenceHelper<(KeyCode, NSEvent.ModifierFlags)>([
        MacroPreference("⌥ option", (.option, .option)),
        MacroPreference("⌃ control", (.control, .control)),
        MacroPreference("⌘ command", (.command, .command)),
        MacroPreference("⇪ caps lock", (.capsLock, .capsLock)),
        MacroPreference("fn", (.function, .function))
    ])

    private static let defaultsFile = fileFromPreferencesFolder("alt-tab-macos-defaults.json")
    private static let userFile = fileFromPreferencesFolder("alt-tab-macos.json")

    static func loadFromDiskAndUpdateValues() {
        do {
            try handleNoFileOrOldFile(userFile)
            rawValues = try loadFromDisk(userFile)
            try rawValues
                    .filter { $0.key != "version" }
                    .forEach { try updateAndValidateFromString($0.key, $0.value) }
        } catch {
            debugPrint("Error loading preferences", error)
            NSApp.terminate(NSApplication.shared)
        }
    }

    static func updateAndValidateFromString(_ valueName: String, _ value: String) throws {
        switch valueName {
        case "maxScreenUsage":
            maxScreenUsage = try CGFloat(CGFloat(value).orThrow() / 100)
        case "maxThumbnailsPerRow":
            maxThumbnailsPerRow = try CGFloat(value).orThrow()
        case "iconSize":
            iconSize = try CGFloat(value).orThrow()
        case "fontHeight":
            fontHeight = try CGFloat(value).orThrow()
            font = NSFont.systemFont(ofSize: fontHeight!)
        case "tabKeyCode":
            tabKeyCode = try UInt16(value).orThrow()
        case "metaKey":
            let p = try metaKeyMacro.labelToMacro[value].orThrow()
            metaKeyCode = p.preferences.0
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
        default:
            throw "Tried to update an unknown preference: '\(valueName)' = '\(value)'"
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

    private static func handleNoFileOrOldFile(_ userFile: URL) throws {
        try saveDefaultsToDisk()
        if !FileManager.default.fileExists(atPath: userFile.path) {
            try FileManager.default.copyItem(at: defaultsFile, to: userFile)
        } else {
            if try preferencesVersion(defaultsFile) > preferencesVersion(userFile) {
                // TODO: handle upgrades in a smarter way (e.g. merge files)
                try FileManager.default.removeItem(at: userFile)
                try FileManager.default.copyItem(at: defaultsFile, to: userFile)
            }
        }
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
