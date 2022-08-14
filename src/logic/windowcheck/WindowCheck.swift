//
// Created by Zachary Wander on 8/14/22.
// Copyright (c) 2022 lwouis. All rights reserved.
//

/**
 The collection of all window checkers.
 If a new check is created, its instance should be added here.
 */
let windowChecks: [WindowCheck] = [
    JetBrainsWindowCheck(),
    IINAWindowCheck(),
    KeyNoteWindowCheck(),
    OpenBoardWindowCheck(),
    AdobeAuditionWindowCheck(),
    BooksWindowCheck(),
    WorldOfWarcraftWindowCheck(),
    BattleNetBootstrapperWindowCheck(),
    DrBetotteWindowCheck(),
    DVDFabWindowCheck(),
    SanGuoShaAirWDWindowCheck(),
    SteamWindowCheck(),
    FirefoxFullscreenVideoWindowCheck(),
    VLCFullscreenVideoWindowCheck(),
    AndroidEmulatorWindowCheck(),
    ColorSlurpWindowCheck()
]

struct WindowCheckOptions {
    var runningApp: NSRunningApplication
    var title: String?
    var subrole: String?
    var wid: CGWindowID
    var level: CGWindowLevel
    var role: String?
    var size: CGSize?
}

/**
 The base class for performing a window exception check.
 Subclasses should override [isValidWindow] and perform checks based
 on the passed [WindowCheckOptions], returning true if the window should
 show in the switcher.
 */
class WindowCheck {
    func check(_ opts: WindowCheckOptions) -> Bool {
        return isValidWindow(opts) && isValidSize(opts.size) && isValidLevel(opts.level)
    }

    /**
     This allows for overriding the default requirements of windows being at least 100x100
     to show in the switcher.
     - Parameter size: the size of the window being checked.
     - Returns: true if the window's size is correct.
     */
    func isValidSize(_ size: CGSize?) -> Bool {
        return size != nil && size!.width > AXUIElement.minWindowSize && size!.height > AXUIElement.minWindowSize
    }

    /**
     Most windows should only show in the switcher if they have a normal level.
     Some apps (Books, KeyNote, IINA) should show up no matter their level.
     - Parameter level: the current window level.
     - Returns: true if the window's level is correct.
     */
    func isValidLevel(_ level: CGWindowLevel) -> Bool {
        return level == CGWindow.normalLevel
    }

    func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        fatalError("Must override!")
    }
}

class JetBrainsWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // jetbrain apps sometimes generate non-windows that pass all checks in isActualWindow
        // they have no title, so we can filter them out based on that
        return opts.runningApp.bundleIdentifier?.range(of: "^com\\.(jetbrains\\.|google\\.android\\.studio).*?$", options: .regularExpression) != nil &&
                (opts.subrole == kAXStandardWindowSubrole || opts.title != nil && opts.title != "")
    }
}

class IINAWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // IINA.app can have videos float (level == 2 instead of 0)
        // there is also complex animations during which we may or may not consider the window not a window
        return opts.runningApp.bundleIdentifier == "com.colliderli.iina"
    }

    override func isValidLevel(_ level: CGWindowLevel) -> Bool {
        return true
    }
}

class KeyNoteWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // apple Keynote has a fake fullscreen window when in presentation mode
        // it covers the screen with a AXUnknown window instead of using standard fullscreen mode
        return opts.runningApp.bundleIdentifier == "com.apple.iWork.Keynote"
    }

    override func isValidLevel(_ level: CGWindowLevel) -> Bool {
        return true
    }
}

class OpenBoardWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // OpenBoard is a ported app which doesn't use standard macOS windows
        return opts.runningApp.bundleIdentifier == "org.oe-f.OpenBoard"
    }
}

class AdobeAuditionWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        return opts.runningApp.bundleIdentifier == "com.adobe.Audition" && opts.subrole == kAXFloatingWindowSubrole
    }
}

class BooksWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // Books.app has animations on window creation. This means windows are originally created with subrole == AXUnknown or isOnNormalLevel == false
        return opts.runningApp.bundleIdentifier == "com.apple.iBooksX"
    }

    override func isValidLevel(_ level: CGWindowLevel) -> Bool {
        return true
    }
}

class WorldOfWarcraftWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        return opts.runningApp.bundleIdentifier == "com.blizzard.worldofwarcraft" && opts.role == kAXWindowRole
    }
}

class BattleNetBootstrapperWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // Battlenet bootstrapper windows have subrole == AXUnknown
        return opts.runningApp.bundleIdentifier == "net.battle.bootstrapper" && opts.role == kAXWindowRole
    }
}

class DrBetotteWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        return opts.runningApp.bundleIdentifier == "com.ssworks.drbetotte"
    }
}

class DVDFabWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        return opts.runningApp.bundleIdentifier == "com.goland.dvdfab.macos"
    }
}

class SanGuoShaAirWDWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        return opts.runningApp.bundleIdentifier == "SanGuoShaAirWD"
    }
}

class SteamWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // All Steam windows have subrole == AXUnknown
        // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
        return opts.runningApp.bundleIdentifier == "com.valvesoftware.steam" && opts.title != "" && opts.role != nil
    }
}

class FirefoxFullscreenVideoWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // Firefox fullscreen video have subrole == AXUnknown if fullscreen'ed when the base window is not fullscreen
        return (opts.runningApp.bundleIdentifier?.hasPrefix("org.mozilla.firefox") ?? false) && opts.role == kAXWindowRole
    }
}

class VLCFullscreenVideoWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // VLC fullscreen video have subrole == AXUnknown if fullscreen'ed
        return (opts.runningApp.bundleIdentifier?.hasPrefix("org.videolan.vlc") ?? false) && opts.role == kAXWindowRole
    }
}

class AndroidEmulatorWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // android emulator small vertical menu is a "window" with empty title; we exclude it
        return opts.title != "" && Applications.isAndroidEmulator(opts.runningApp)
    }
}

class ColorSlurpWindowCheck : WindowCheck {
    override func isValidWindow(_ opts: WindowCheckOptions) -> Bool {
        // ColorSlurp presents its dialog as a kAXSystemDialogSubrole, so we need a special check
        return opts.runningApp.bundleIdentifier == "com.IdeaPunch.ColorSlurp"
    }
}
