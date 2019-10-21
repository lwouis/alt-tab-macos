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
        if Preferences.thumbnailMaxWidth == 0 && Preferences.thumbnailMaxHeight == 0 {
            do {
                let main = NSScreen.main!.frame
                try Preferences.updateAndValidateValue("thumbnailMaxWidth", 
                        String((NSScreen.main!.frame.size.width * Preferences.maxScreenUsage - Preferences.windowPadding * 2) / Preferences.maxThumbnailsPerRow - Preferences.interItemPadding).orThrow())
                try Preferences.updateAndValidateValue("thumbnailMaxHeight",
                        String(Preferences.thumbnailMaxWidth * (main.height / main.width)).orThrow())
                try Preferences.saveRawToDisk()
            } catch {
                debugPrint("Error updating preferences based on screen size", error)
                NSApp.terminate(NSApplication.shared)
            }
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
