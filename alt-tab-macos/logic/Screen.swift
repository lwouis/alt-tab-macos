import Foundation
import Cocoa

class Screen {
    // currently not in use (but kept for reference & future use), earlier registered by Application.applicationDidFinishLaunching()
    static func listenToChanges() {
        NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: NSApplication.shared,
                queue: OperationQueue.main
        ) { notification -> Void in
            // do something
        }
    }

    static func calcThumbnailMaxSize(_ screen: NSScreen) -> NSSize {
        let width: CGFloat = (screen.frame.size.width * Preferences.maxScreenUsage! - Preferences.windowPadding * 2) / Preferences.maxThumbnailsPerRow! - Preferences.interItemPadding
        let height: CGFloat = width * (screen.frame.height / screen.frame.width)
        return NSSize(width: width, height: height)
    }

    static func calcFrameMaxSize(_ screen: NSScreen) -> NSSize {
        return NSSize(width: screen.frame.width * Preferences.maxScreenUsage!, height: screen.frame.height * Preferences.maxScreenUsage!)
    }

    // TODO: currently unknown and unhandled error use-case possible: NSScreen.main being nil
    static func getPreferredScreen() -> NSScreen {
        switch Preferences.showOnScreen! {
        case .MOUSE:
            return getScreenWithMouse() ?? NSScreen.main!; // .main as fall-back
        case .MAIN:
            return NSScreen.main!;
        }
    }

    static func getScreenWithMouse() -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    /*
    usage notes:
    - useAppleVerticalOffset: applies a vertical offset (higher positioning) attempting to approximate the NSView.center() results but only if we are not dealing with screen filling frames (height)
    */
    static func showCenteredFrontPanel(_ panel: NSPanel, _ screen: NSScreen, _ useAppleVerticalOffset: Bool = true) {
        var verticalOffset: CGFloat = 0

        if useAppleVerticalOffset && panel.frame.height < screen.visibleFrame.height / 1.5 {
            verticalOffset = CGFloat(screen.visibleFrame.height * 0.175)
        }

        let centerPosition = NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2 + verticalOffset)
        panel.setFrameOrigin(centerPosition)
        panel.makeKeyAndOrderFront(nil)
        Application.shared.arrangeInFront(nil)
    }
}
