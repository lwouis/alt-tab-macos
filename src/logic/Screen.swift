import Cocoa

class Screen {
    static func preferred() -> NSScreen {
        switch Preferences.showOnScreen {
            case .includingMouse: return withMouse() ?? NSScreen.main! // .main as fall-back
            case .active: return NSScreen.main!
            case .includingMenubar: return NSScreen.screens.first!
        }
    }

    private static func withMouse() -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    static func repositionPanel(_ window: NSWindow, _ screen: NSScreen, _ alignment: VerticalAlignment) {
        let screenFrame = screen.visibleFrame
        let panelFrame = window.frame
        let x = screenFrame.minX + max(screenFrame.width - panelFrame.width, 0) * 0.5
        let y = screenFrame.minY + max(screenFrame.height - panelFrame.height, 0) * alignment.rawValue
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    static func uuid(_ screen: NSScreen) -> ScreenUuid {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
        let screenUuid = CGDisplayCreateUUIDFromDisplayID(screenNumber).takeRetainedValue()
        return CFUUIDCreateString(nil, screenUuid)!
    }
}

enum VerticalAlignment: CGFloat {
    case centered = 0.5
    // vertically centered but with an upward offset, similar to a book title; mimics NSView.center()
    case appleCentered = 0.75
}

typealias ScreenUuid = CFString
