import Cocoa

class Screens {
    static var all = [ScreenUuid: NSScreen]()

    static func refresh() {
        all.removeAll()
        NSScreen.clearUuidCache()
        for screen in NSScreen.screens {
            guard let uuid = screen.cachedUuid() else { continue }
            all[uuid] = screen
        }
    }
}

extension NSScreen {
    static var preferred = NSScreen.screens.first!
    private static var uuidCache = [ObjectIdentifier: ScreenUuid]()

    /// During a display reconfiguration (unplug, sleep, resolution change) `NSScreen.screens` can be
    /// empty for a moment, and the notification that tells us to recompute arrives in that window.
    /// There is no valid NSScreen to fall back to then (`NSScreen()` crashes on access), so we keep
    /// the last known screen until the display list comes back.
    static func updatePreferred() {
        if let screen = detectPreferred() ?? NSScreen.screens.first {
            preferred = screen
        }
    }

    private static func detectPreferred() -> NSScreen? {
        switch Preferences.showOnScreen {
            case .includingMouse: return withMouse()
            case .active: return NSScreen.active()
            case .includingMenubar: return NSScreen.screens.first
        }
    }

    /// NSScreen.main docs are incorrect. It stopped returning the screen with the key window in macOS 10.9
    /// see https://stackoverflow.com/a/56268826/2249756
    /// There are a few cases where .main doesn't return the screen with the key window:
    ///   * if the active screen shows a fullscreen app, it always returns screens[0]
    ///   * if NSScreen.screensHaveSeparateSpaces == false, and key window is on another screen than screens[0], it still returns screens[0]
    /// we find the screen with the key window ourselves manually
    static func active() -> NSScreen? {
        guard case .window(let identity) = AttentionEngine.currentUserContext,
              let focusedWindow = Windows.byWindowId[identity.wid] else { return NSScreen.withActiveMenubar() }
        // Read the focused window's cached screen rather than refreshing it here: this runs on the show
        // path (NSScreen.updatePreferred), and updateSpacesAndScreen() does a synchronous CGS call (#5721).
        // The screen is kept fresh off-main on focus events and by Applications.syncSpacesState; the only
        // cost is a possibly-wrong active screen on the very first summon of a never-yet-resolved window.
        guard let screenId = focusedWindow.screenId else { return NSScreen.withActiveMenubar() }
        return Screens.all[screenId] ?? NSScreen.withActiveMenubar()
    }

    /// there is only 1 active menubar. Other screens will show their menubar dimmed.
    /// The identifier is hoisted out of the predicate: it does not vary per screen, and inside `first { }` it
    /// was a synchronous WindowServer round trip PER SCREEN, on the main thread, on the show path.
    static func withActiveMenubar() -> NSScreen? {
        let activeMenubarUuid = CGSCopyActiveMenuBarDisplayIdentifier(CGS_CONNECTION)
        return NSScreen.screens.first { activeMenubarUuid == $0.cachedUuid() }
    }

    static func withMouse() -> NSScreen? {
        return NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    /// `NSEvent.mouseLocation` is in Cocoa coordinates (origin at the bottom-left of the main screen); window
    /// frames from AX and the WindowServer are in Quartz coordinates (origin at its top-left), so the y axis is
    /// flipped around the main screen's height, as in `Window.isOnScreen`.
    static func mouseLocationInQuartzCoordinates() -> CGPoint {
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x, y: NSMaxY(NSScreen.screens[0].frame) - location.y)
    }

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
        guard let screenNumber = number(),
        // these APIs implicitly unwrap their return values, but it can actually be nil thus we check
        let screenUuid = CGDisplayCreateUUIDFromDisplayID(screenNumber),
        let uuid = CFUUIDCreateString(nil, screenUuid.takeRetainedValue()) else { return nil }
        return uuid
    }

    static func clearUuidCache() {
        uuidCache.removeAll(keepingCapacity: true)
    }

    func cachedUuid() -> ScreenUuid? {
        let key = ObjectIdentifier(self)
        if let uuid = NSScreen.uuidCache[key] { return uuid }
        guard let uuid = uuid() else { return nil }
        NSScreen.uuidCache[key] = uuid
        return uuid
    }

    // periphery:ignore
    func refreshRate() -> Double? {
        return number().flatMap { CGDisplayCopyDisplayMode($0)?.refreshRate }
    }

    func physicalSize() -> CGSize? {
        if let number = number() {
            let size = CGDisplayScreenSize(number)
            // CGDisplayScreenSize docs says it can return "zero"
            if size.width > 0 && size.height > 0 &&
                   // CGDisplayScreenSize may return wrong values; we compare physical and logical ratios to reject
                   abs(ratio() - (size.width / size.height)) < 0.2 {
                return size
            }
        }
        return nil
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
