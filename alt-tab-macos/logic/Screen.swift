import Cocoa

class Screen {
    static func preferred() -> NSScreen {
        switch Preferences.showOnScreen! {
            case .MOUSE: return withMouse() ?? NSScreen.main!; // .main as fall-back
            case .MAIN: return NSScreen.main!;
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

    static func mainUuid() -> CFString {
        return "Main" as CFString
        // the bellow code gets the actual main screen, but in our case we seem to be fine with sending "Main"
        // our only need for this is for the System Preferences panel which has incorrect space with or without this
        //let mainScreenId = NSScreen.main!.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
        //return CFUUIDCreateString(nil, CGDisplayCreateUUIDFromDisplayID(mainScreenId).takeRetainedValue())!
    }
}

enum VerticalAlignment: CGFloat {
    case centered = 0.5
    // vertically centered but with an upward offset, similar to a book title; mimics NSView.center()
    case appleCentered = 0.75
}
