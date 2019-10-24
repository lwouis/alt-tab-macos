import Foundation
import Cocoa

class Screen {
    static func listenToChanges() {
        NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: NSApplication.shared,
                queue: OperationQueue.main
        ) { notification -> Void in
            updateThumbnailMaxSize()
        }
    }

    static func updateThumbnailMaxSize() -> Void {
        if Preferences.thumbnailMaxWidth == 200 && Preferences.thumbnailMaxHeight == 200 {
            let main = NSScreen.main!.frame
            Preferences.thumbnailMaxWidth = (NSScreen.main!.frame.size.width * Preferences.maxScreenUsage! - Preferences.windowPadding * 2) / Preferences.maxThumbnailsPerRow! - Preferences.interItemPadding
            Preferences.thumbnailMaxHeight = Preferences.thumbnailMaxWidth * (main.height / main.width)
        }
    }
}

// add String constructor from CGFloat that round up at 1 decimal
extension String {
    init?(_ cgFloat: CGFloat) {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        guard let string = formatter.string(from: cgFloat as NSNumber) else {
            return nil
        }
        self.init(string)
    }
}
