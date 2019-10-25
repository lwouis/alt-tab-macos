import Foundation
import Cocoa

let defaults = [
    "version": "1", // bump this anytime the dictionary is changed
    "maxScreenUsage": "0.8",
    "maxThumbnailsPerRow": "4",
    "iconSize": "32",
    "fontHeight": "15",
    "tabKey": String(KeyCode.tab.rawValue),
    "metaKey": Preferences.metaKeyArray[0],
    "windowDisplayDelay": "0",
    "theme": Preferences.themeArray[0]
]

class Preferences {
    static var rawValues = [String: String]()
    static var thumbnailMaxWidth: CGFloat = 200
    static var thumbnailMaxHeight: CGFloat = 200
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
    static var tabKey: UInt16?
    static var highlightBorderColor: NSColor?
    static var highlightBackgroundColor: NSColor?
    static var metaKeyCode: KeyCode?
    static var metaModifierFlag: NSEvent.ModifierFlags?
    static var windowDisplayDelay: DispatchTimeInterval?
    static var windowCornerRadius: CGFloat?
    static var font: NSFont?
    static var themeArray = [" macOS", "❖ Windows 10"]
    static var metaKeyArray = ["⌥ option", "⌃ control", "⌘ command", "⇪ caps lock", "fn"]
    static var metaKeyMap: [String: (KeyCode, NSEvent.ModifierFlags)] = [
        metaKeyArray[0]: (KeyCode.tab, .option),
        metaKeyArray[1]: (KeyCode.control, .control),
        metaKeyArray[2]: (KeyCode.command, .command),
        metaKeyArray[3]: (KeyCode.capsLock, .capsLock),
        metaKeyArray[4]: (KeyCode.function, .function),
    ]

    private static let defaultsFile = fileFromPreferencesFolder("alt-tab-macos-defaults.json")
    private static let userFile = fileFromPreferencesFolder("alt-tab-macos.json")

    static func loadFromDiskAndUpdateValues() {
        do {
            try handleNoFileOrOldFile(userFile)
            rawValues = try loadFromDisk(userFile)
            try rawValues
                    .filter {
                        $0.key != "version"
                    }
                    .forEach {
                        try updateAndValidateFromString($0.key, $0.value)
                    }
        } catch {
            debugPrint("Error loading preferences", error)
            NSApp.terminate(NSApplication.shared)
        }
    }

    static func updateAndValidateFromString(_ valueName: String, _ value: String) throws {
        switch valueName {
        case "maxScreenUsage":
            maxScreenUsage = try CGFloat(value).orThrow()
        case "maxThumbnailsPerRow":
            maxThumbnailsPerRow = try CGFloat(value).orThrow()
        case "iconSize":
            iconSize = try CGFloat(value).orThrow()
        case "fontHeight":
            fontHeight = try CGFloat(value).orThrow()
            font = NSFont.systemFont(ofSize: fontHeight!)
        case "tabKey":
            tabKey = try UInt16(value).orThrow()
        case "metaKey":
            let (keyCode, modifierFlag) = try metaKeyMap[value].orThrow()
            metaKeyCode = keyCode
            metaModifierFlag = modifierFlag
        case "theme":
            let isMac = value == themeArray[0]
            cellBorderWidth = isMac ? 0 : 2
            cellCornerRadius = isMac ? 5 : 0
            highlightBorderColor = isMac ? .clear : .white
            highlightBackgroundColor = isMac ? NSColor(red: 0, green: 0, blue: 0, alpha: 0.15) : .clear
            windowCornerRadius = isMac ? 20 : 0
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
        try Int(loadFromDisk(url)["version"] ?? "0").orThrow()
    }

    private static func loadFromDisk(_ url: URL) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
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
        FileManager.default
                .urls(for: .libraryDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Preferences", isDirectory: true)
                .appendingPathComponent(fileName)
    }
}

// add CGFloat constructor from String
extension CGFloat {
    init?(_ string: String) {
        guard let number = NumberFormatter().number(from: string) else {
            return nil
        }
        self.init(number.floatValue)
    }
}

// add throw-on-nil method on Optional
extension Optional {
    func orThrow() throws -> Wrapped {
        switch self {
        case .some(let value):
            return value
        case .none:
            Thread.callStackSymbols.forEach {
                print($0)
            }
            throw "Optional contained nil"
        }
    }
}

// allow String to be treated as Error (e.g. throw "explanation")
extension String: Error {
}
