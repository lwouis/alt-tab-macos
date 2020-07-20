import Cocoa

class Screen {
    static func mainScreenRatio() -> CGFloat {
        let mainScreen = NSScreen.main!.frame
        return mainScreen.width / mainScreen.height
    }

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

    static func uuid(_ screen: NSScreen) -> ScreenUuid? {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
        // this api from apple lies in its signature; the return value can be nil; we cast to remove the warning
        let screenUuid = CGDisplayCreateUUIDFromDisplayID(screenNumber).takeRetainedValue() as CFUUID?
        if screenUuid != nil,
           let uuid = CFUUIDCreateString(nil, screenUuid) {
            return uuid
        }
        return nil
    }
}

enum VerticalAlignment: CGFloat {
    case centered = 0.5
    // vertically centered but with an upward offset, similar to a book title; mimics NSView.center()
    case appleCentered = 0.75
}

typealias ScreenUuid = CFString
