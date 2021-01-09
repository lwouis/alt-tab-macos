import Cocoa

extension NSScreen {
    func ratio() -> CGFloat {
        return frame.width / frame.height
    }

    func refreshRate() -> Double? {
        if let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID,
            let screenMode = CGDisplayCopyDisplayMode(screenNumber)
        {
            return screenMode.refreshRate
        }
        return nil
    }

    static func preferred() -> NSScreen {
        switch Preferences.showOnScreen {
        case .includingMouse: return withMouse() ?? NSScreen.main!  // .main as fall-back
        case .active: return NSScreen.main!  // macOS bug: this will return screens[0] if the main screen shows a fullscreen app
        case .includingMenubar: return NSScreen.screens.first!
        }
    }

    static func withMouse() -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    func repositionPanel(_ window: NSWindow, _ alignment: VerticalAlignment) {
        let screenFrame = visibleFrame
        let panelFrame = window.frame
        let x = screenFrame.minX + max(screenFrame.width - panelFrame.width, 0) * 0.5
        let y =
            screenFrame.minY + max(screenFrame.height - panelFrame.height, 0) * alignment.rawValue
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func uuid() -> ScreenUuid? {
        if let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")],
            // these APIs implicitly unwrap their return values, but it can actually be nil thus we check
            let screenUuid = CGDisplayCreateUUIDFromDisplayID(screenNumber as! UInt32),
            let uuid = CFUUIDCreateString(nil, screenUuid.takeRetainedValue())
        {
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
