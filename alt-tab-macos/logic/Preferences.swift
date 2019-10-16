import Foundation
import Cocoa

struct PreferencesDecodable: Decodable {
    let maxScreenUsage: CGFloat?
    let windowPadding: CGFloat?
    let cellPadding: CGFloat?
    let cellBorderWidth: CGFloat?
    let maxThumbnailsPerRow: CGFloat?
    let thumbnailMaxWidth: CGFloat?
    let thumbnailMaxHeight: CGFloat?
    let iconSize: CGFloat?
    let fontHeight: CGFloat?
    let interItemPadding: CGFloat?
    let tabKey: UInt16?
    let metaKey: UInt16?
    let metaModifierFlagInt: UInt?
    let highlightColorString : String?
    let thumbnailQuality : UInt?
}

func fileLines(_ url: URL) throws -> Int {
    try String(contentsOf: url, encoding: .utf8).split(separator: "\n").count
}

class Preferences: Decodable {
    private static let decoded: PreferencesDecodable? = decodeFromJson()

    private static func decodeFromJson() -> PreferencesDecodable? {
        do {
            let defaultFile = Bundle.main.url(forResource: "preferences", withExtension: "json")!
            let userFile = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
                    .first!
                    .appendingPathComponent("Preferences", isDirectory: true)
                    .appendingPathComponent("alt-tab-macos.json")
            try handleNoFileOrOldFile(userFile: userFile, defaultFile: defaultFile)
            return try JSONDecoder().decode(PreferencesDecodable.self, from: Data(contentsOf: userFile))
        } catch {
            debugPrint("Error parsing preferences.json", error)
            return nil
        }
    }

    private static func handleNoFileOrOldFile(userFile: URL, defaultFile: URL) throws {
        if !FileManager.default.fileExists(atPath: userFile.path) {
            try FileManager.default.copyItem(at: defaultFile, to: userFile)
        } else if try fileLines(defaultFile) > fileLines(userFile) {
            // TODO: handle upgrades in a smarter way (e.g. merge files)
            let _ = try FileManager.default.replaceItemAt(defaultFile, withItemAt: userFile)
        }
    }

    // maximum width/height of the main window, in percentage of screen width/height
    static let maxScreenUsage = decoded?.maxScreenUsage ?? 0.8
    // padding in the main window
    static let windowPadding = decoded?.windowPadding ?? 20
    // padding in each cell
    static let cellPadding = decoded?.cellPadding ?? 6
    // border width of each cell
    static let cellBorderWidth = decoded?.cellBorderWidth ?? 2
    // maximum number of thumbnails on each row
    static let maxThumbnailsPerRow = decoded?.maxThumbnailsPerRow ?? 4
    // maximum width of each thumbnail
    static var thumbnailMaxWidth = decoded?.thumbnailMaxWidth ?? 0
    // maximum height of eacg thumbnail
    static var thumbnailMaxHeight = decoded?.thumbnailMaxHeight ?? 0
    // width/height for each cell app icon
    static let iconSize = decoded?.iconSize ?? 32
    // font height for each cell title
    static let fontHeight = decoded?.fontHeight ?? 15
    // padding between cells within the main window
    static let interItemPadding = decoded?.interItemPadding ?? 4
    // NSEvent.keyCode (e.g. leftCommand=55, leftOption=58, leftControl=59, rightCommand=54, rightOption=61)
    static let tabKey = decoded?.tabKey ?? 48
    // NSEvent.keyCode (e.g. leftCommand=55, leftOption=58, leftControl=59, rightCommand=54, rightOption=61)
    static let metaKey = decoded?.metaKey ?? 59
    // NSImageInterpolation (e.g. none=1, low=2, medium=4, high=3)
    static let thumbnailQuality = NSImageInterpolation.init(rawValue: decoded?.thumbnailQuality ?? 3) ?? .high
    // NSEvent.ModifierFlags (e.g. control=262144, command=1048576, shift=131072, option=524288)
    static let metaModifierFlag = NSEvent.ModifierFlags(rawValue: decoded?.metaModifierFlagInt ?? 262144)
    // color for the currently selected cell
    static let highlightColor = NSColor.white
    // derived properties
    static let font: NSFont = .systemFont(ofSize: Preferences.fontHeight)
}

