import Cocoa

extension NSScreen {
    func ratio() -> CGFloat {
        return frame.width / frame.height
    }

    func isHorizontal() -> Bool {
        return ratio() >= 1
    }

    func number() -> CGDirectDisplayID? {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    func uuid() -> ScreenUuid? {
        if let screenNumber = number(),
           // these APIs implicitly unwrap their return values, but it can actually be nil thus we check
           let screenUuid = CGDisplayCreateUUIDFromDisplayID(screenNumber as! UInt32),
           let uuid = CFUUIDCreateString(nil, screenUuid.takeRetainedValue()) {
            return uuid
        }
        return nil
    }

    // periphery:ignore
    func refreshRate() -> Double? {
        return number().map { CGDisplayCopyDisplayMode($0)?.refreshRate }
    }

    func physicalSize() -> CGSize? {
        return number().map { CGDisplayScreenSize($0) }
    }

    static func preferred() -> NSScreen {
        preferred_() ?? NSScreen.screens.first!
    }

    private static func preferred_() -> NSScreen? {
        switch Preferences.showOnScreen {
            case .includingMouse: return withMouse()
            case .active: return NSScreen.active()
            case .includingMenubar: return NSScreen.screens.first
        }
    }

    // NSScreen.main docs are incorrect. It stopped returning the screen with the key window in macOS 10.9

    // see https://stackoverflow.com/a/56268826/2249756
    // There are a few cases where .main doesn't return the screen with the key window:
    //   * if the active screen shows a fullscreen app, it always returns screens[0]
    //   * if NSScreen.screensHaveSeparateSpaces == false, and key window is on another screen than screens[0], it still returns screens[0]
    // we find the screen with the key window ourselves manually
    static func active() -> NSScreen? {
        if let app = Applications.find(NSWorkspace.shared.frontmostApplication?.processIdentifier) {
            if let focusedWindow = app.focusedWindow {
                return NSScreen.screens.first { focusedWindow.isOnScreen($0) }
            }
            return NSScreen.withActiveMenubar()
        }
        return nil
    }

    // there is only 1 active menubar. Other screens will show their menubar dimmed
    static func withActiveMenubar() -> NSScreen? {
        return NSScreen.screens.first { CGSCopyActiveMenuBarDisplayIdentifier(cgsMainConnectionId) == $0.uuid() }
    }

    static func withMouse() -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    func repositionPanel(_ window: NSWindow) {
        let screenFrame = visibleFrame
        let panelFrame = window.frame
        let x = screenFrame.minX + max(screenFrame.width - panelFrame.width, 0) * 0.5
        let y = screenFrame.minY + max(screenFrame.height - panelFrame.height, 0) * 0.5
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

typealias ScreenUuid = CFString
