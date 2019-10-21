import Foundation
import Cocoa

let defaults = [
    "maxScreenUsage": "0.8",
    "windowPadding": "20",
    "cellPadding": "6",
    "cellBorderWidth": "2",
    "maxThumbnailsPerRow": "4",
    "thumbnailMaxWidth": "0",
    "thumbnailMaxHeight": "0",
    "iconSize": "32",
    "fontHeight": "15",
    "interItemPadding": "4",
    "tabKey": "48",
    "metaKey": "59",
    "metaModifierFlag": "262144",
    "highlightColor": "white",
    "thumbnailQuality": "4",
    "windowDisplayDelay": "200",
]

class Preferences {
    static var rawValues = [String: String]()
    static var maxScreenUsage: CGFloat = 0
    static var windowPadding: CGFloat = 0
    static var cellPadding: CGFloat = 0
    static var cellBorderWidth: CGFloat = 0
    static var maxThumbnailsPerRow: CGFloat = 0
    static var thumbnailMaxWidth: CGFloat = 0
    static var thumbnailMaxHeight: CGFloat = 0
    static var iconSize: CGFloat = 0
    static var fontHeight: CGFloat = 0
    static var interItemPadding: CGFloat = 0
    static var tabKey: UInt16 = 0
    static var metaKey: UInt16 = 0
    static var metaModifierFlag: NSEvent.ModifierFlags = .control
    static var highlightColor: NSColor = .white
    static var thumbnailQuality: NSImageInterpolation = .high
    static var windowDisplayDelay: DispatchTimeInterval = .milliseconds(200)
    static var font: NSFont = .systemFont(ofSize: 15)

    private static let defaultsFile = fileFromPreferencesFolder("alt-tab-macos-defaults.json")
    private static let userFile = fileFromPreferencesFolder("alt-tab-macos.json")

    static func loadFromDiskAndUpdateValues() {
        do {
            rawValues = try loadFromDisk()
            try rawValues.forEach {
                try updateAndValidateValue($0.key, $0.value)
            }
        } catch {
            debugPrint("Error loading preferences from JSON file on disk", error)
            NSApp.terminate(NSApplication.shared)
        }
    }

    static func updateAndValidateValue(_ valueName: String, _ value: String) throws {
        switch valueName {
        case "maxScreenUsage":
            maxScreenUsage = try CGFloat(value).orThrow()
        case "windowPadding":
            windowPadding = try CGFloat(value).orThrow()
        case "cellPadding":
            cellPadding = try CGFloat(value).orThrow()
        case "cellBorderWidth":
            cellBorderWidth = try CGFloat(value).orThrow()
        case "maxThumbnailsPerRow":
            maxThumbnailsPerRow = try CGFloat(value).orThrow()
        case "thumbnailMaxWidth":
            thumbnailMaxWidth = try CGFloat(value).orThrow()
        case "thumbnailMaxHeight":
            thumbnailMaxHeight = try CGFloat(value).orThrow()
        case "iconSize":
            iconSize = try CGFloat(value).orThrow()
        case "fontHeight":
            fontHeight = try CGFloat(value).orThrow()
        case "interItemPadding":
            interItemPadding = try CGFloat(value).orThrow()
        case "tabKey":
            tabKey = try UInt16(value).orThrow()
        case "metaKey":
            metaKey = try UInt16(value).orThrow()
        case "metaModifierFlag":
            metaModifierFlag = NSEvent.ModifierFlags(rawValue: try UInt(value).orThrow())
        case "highlightColor":
            highlightColor = NSColor.white
        case "thumbnailQuality":
            thumbnailQuality = NSImageInterpolation(rawValue: try UInt(value).orThrow())!
        case "windowDisplayDelay":
            windowDisplayDelay = DispatchTimeInterval.milliseconds(try Int(value).orThrow())
        case "font":
            font = NSFont.systemFont(ofSize: fontHeight)
        default:
            throw "Tried to update an unknown preference"
        }
        rawValues[valueName] = value
    }

    static func saveRawToDisk() throws {
        try saveToDisk(rawValues, userFile)
    }

    private static func fileLines(_ url: URL) throws -> Int {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count
    }

    private static func loadFromDisk() throws -> [String: String] {
        try handleNoFileOrOldFile(userFile)
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: userFile))
    }

    private static func handleNoFileOrOldFile(_ userFile: URL) throws {
        if !FileManager.default.fileExists(atPath: defaultsFile.path) {
            try saveDefaultsToDisk()
        }
        if !FileManager.default.fileExists(atPath: userFile.path) {
            try FileManager.default.copyItem(at: defaultsFile, to: userFile)
        } else {
            if try fileLines(defaultsFile) > fileLines(userFile) {
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
            throw "Optional contained nil"
        }
    }
}

// allow String to be treated as Error (e.g. throw "explanation")
extension String: Error {
}
