import Foundation
import Cocoa

class Screen {
    static func preferred() -> NSScreen {
        switch Preferences.showOnScreen! {
        case .MOUSE:
            return withMouse() ?? NSScreen.main!; // .main as fall-back
        case .MAIN:
            return NSScreen.main!;
        }
    }

    private static func withMouse() -> NSScreen? {
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

    static func screenContaining(_ rect: CGRect) -> NSScreen? {
        var screenContainingMost = NSScreen.main
        var largestPercentageContained = CGFloat(0)
        for screen in NSScreen.screens {
            let frame = NSRectToCGRect(screen.frame)
            let rect = normalizeCoordinatesOf(rect, frame)
            if frame.contains(rect) {
                return screen
            }
            let percentageContained = percentageOf(rect, frame)
            if percentageContained > largestPercentageContained {
                largestPercentageContained = percentageContained
                screenContainingMost = screen
            }
        }
        return screenContainingMost
    }

    private static func normalizeCoordinatesOf(_ rect: CGRect, _ frameOfScreen: CGRect) -> CGRect {
        var normalizedRect = rect
        let frameOfScreenWithMenuBar = NSScreen.screens[0].frame as CGRect
        normalizedRect.origin.y = frameOfScreen.size.height - rect.maxY + (frameOfScreenWithMenuBar.size.height - frameOfScreen.size.height)
        return normalizedRect
    }

    private static func percentageOf(_ rect: CGRect, _ frame: CGRect) -> CGFloat {
        let intersection = rect.intersection(frame)
        if intersection.isNull {
            return CGFloat(0)
        }
        return rectArea(intersection) / rectArea(rect)
    }

    private static func rectArea(_ rect: CGRect) -> CGFloat {
        return rect.size.width * rect.size.height
    }
}

enum WindowPosition {
    case leftHalf
    case rightHalf
}

enum VerticalAlignment: CGFloat {
    case centered = 0.5
    // vertically centered but with an upward offset, similar to a book title; mimics NSView.center()
    case appleCentered = 0.75
}
