import Foundation
import Cocoa

class Screen {
    static func preferredScreen() -> NSScreen {
        switch Preferences.showOnScreen! {
        case .MOUSE:
            return screenWithMouse() ?? NSScreen.main!; // .main as fall-back
        case .MAIN:
            return NSScreen.main!;
        }
    }

    private static func screenWithMouse() -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    static func thumbnailMaxSize(_ screen: NSScreen) -> NSSize {
        let frame = screen.visibleFrame
        let width = (frame.width * Preferences.maxScreenUsage! - Preferences.windowPadding * 2) / Preferences.maxThumbnailsPerRow! - Preferences.interItemPadding
        let height = width * (frame.height / frame.width)
        return NSSize(width: width, height: height)
    }

    static func thumbnailPanelMaxSize(_ screen: NSScreen) -> NSSize {
        let frame = screen.visibleFrame
        return NSSize(width: frame.width * Preferences.maxScreenUsage!, height: frame.height * Preferences.maxScreenUsage!)
    }

    static func showPanel(_ panel: NSPanel, _ screen: NSScreen, _ alignment: VerticalAlignment) {
        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        let x = screenFrame.minX + max(screenFrame.width - panelFrame.width, 0) * 0.5
        let y = screenFrame.minY + max(screenFrame.height - panelFrame.height, 0) * alignment.rawValue
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        Application.shared.arrangeInFront(nil)
    }
}

enum VerticalAlignment: CGFloat {
    case centered = 0.5
    // vertically centered but with an upward offset, similar to a book title; mimics NSView.center()
    case appleCentered = 0.75
}
