import Foundation

enum ProFeatureCopy {
    static let appIconsAndTitles = NSLocalizedString("App Icons & Titles styles", comment: "")
    static let search = NSLocalizedString("Search — find a window by typing", comment: "")
    static let autoSize = NSLocalizedString("Auto Size — larger previews with few windows, more at once with many", comment: "")
    static let extraShortcuts = NSLocalizedString("Up to 9 shortcuts", comment: "")
    static let purchaseTerms = NSLocalizedString("One-time purchase", comment: "Purchase terms shown before opening the website")
    static let trialSetup = NSLocalizedString("Your Pro trial starts when AltTab is ready", comment: "Permissions setup is not finished")
    static let trialPromise = NSLocalizedString("After that, window switching and thumbnails stay free. Search, extra styles, Auto Size, and additional shortcuts require Pro.", comment: "What remains free after the Pro trial")

    static func includedUntil(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return String(format: NSLocalizedString("Pro is included until %@.", comment: "%@ is the localized trial end date"), formatter.string(from: date))
    }
}
