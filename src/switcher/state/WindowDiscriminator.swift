class WindowDiscriminator {
    static func isActualWindow(_ app: Application, _ wid: CGWindowID, _ level: CGWindowLevel, _ title: String?, _ subrole: String?, _ role: String?, _ size: CGSize?) -> Bool {
        // Some non-windows have title: nil (e.g. some OS elements)
        // Some non-windows have subrole: nil (e.g. some OS elements), "AXUnknown" (e.g. Bartender), "AXSystemDialog" (e.g. Intellij tooltips)
        // Minimized windows or windows of a hidden app have subrole "AXDialog"
        // Activity Monitor main window subrole is "AXDialog" for a brief moment at launch; it then becomes "AXStandardWindow"
        // Some non-windows have cgWindowId == 0 (e.g. windows of apps starting at login with the checkbox "Hidden" checked)
        guard wid != 0 else {
            Logger.debug { logTemplate("wid is 0", app, wid, level, title, subrole, role, size) }
            return false
        }
        guard let size else {
            Logger.debug { logTemplate("it has no size", app, wid, level, title, subrole, role, size) }
            return false
        }
        guard size.width > 100 && size.height > 50 else {
            Logger.debug { logTemplate("size is \(Int(size.width))x\(Int(size.height)) which is < 100x50", app, wid, level, title, subrole, role, size) }
            return false
        }
        // ordered cheapest-first so `||`/`&&` short-circuit; nothing below is computed unless needed.
        // a standard subrole (the overwhelmingly common case) accepts before any per-app work; the per-app
        // chains — string compares plus a KERN_PROCARGS sysctl for bundle-id-less apps (androidEmulator) —
        // run only for the rare non-standard window. isSpecialApp is re-checked below but only reaches that
        // line on the rare accepted-non-standard path; the common case evaluates it at most once.
        guard isStandardSubrole(subrole) || isSpecialApp(app, title, subrole, role, level) || appSpecificSubrole(app, title, role, subrole, size) else {
            Logger.debug { logTemplate("subrole is '\(subrole ?? "nil")' instead of '\(kAXStandardWindowSubrole)'/'\(kAXDialogSubrole)'", app, wid, level, title, subrole, role, size) }
            return false
        }
        if !isSpecialApp(app, title, subrole, role, level) {
            guard mustHaveIfJetbrainApp(app, title, subrole, size) &&
                mustHaveIfSteam(app, title, role) &&
                mustHaveIfFusion360(app, title, role) &&
                mustHaveIfColorSlurp(app, subrole) &&
                mustHaveIfAndroidEmulator(app, title) else {
                Logger.debug { logTemplate("of a hardcoded rule for this app", app, wid, level, title, subrole, role, size) }
                return false
            }
        }
        Logger.debug { logTemplate(nil, app, wid, level, title, subrole, role, size) }
        return true
    }

    private static func logTemplate(_ rejectionReason: String?, _ app: Application, _ wid: CGWindowID, _ level: CGWindowLevel, _ title: String?, _ subrole: String?, _ role: String?, _ size: CGSize?) -> String {
        "Window \(rejectionReason == nil ? "accepted" : "rejected") \(app.debugId)\(rejectionReason == nil ? "" : " because \(rejectionReason)") \((wid, level, title, subrole, role, size))"
    }

    private static func isStandardSubrole(_ subrole: String?) -> Bool {
        return [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole)
    }

    private static func isSpecialApp(_ app: Application, _ title: String?, _ subrole: String?, _ role: String?, _ level: CGWindowLevel) -> Bool {
        return books(app) || keynote(app) || preview(app, subrole) || iina(app) ||
            openFlStudio(app, title) || crossoverWindow(app, role, subrole, level) ||
            isAlwaysOnTopScrcpy(app, level, role, subrole)
    }

    private static func appSpecificSubrole(_ app: Application, _ title: String?, _ role: String?, _ subrole: String?, _ size: CGSize?) -> Bool {
        return openBoard(app) || adobeAudition(app, subrole) || adobeAfterEffects(app, subrole) ||
            adobePremierePro(app, subrole) ||
            steam(app, title, role) || worldOfWarcraft(app, role) || battleNetBootstrapper(app, role) ||
            firefox(app, role, size) || vlcFullscreenVideo(app, role) || sanGuoShaAirWD(app) ||
            dvdFab(app) || drBetotte(app) || androidEmulator(app, title) || autocad(app, subrole)
    }

    private static func mustHaveIfFusion360(_ app: Application, _ title: String?, _ role: String?) -> Bool {
        // filter out Autodesk Fusion side panels "Browser" and "Comments" with subrole AXDialog but with no title
        return app.bundleIdentifier != "com.autodesk.fusion360" || (title != nil && title != "")
    }

    private static func mustHaveIfJetbrainApp(_ app: Application, _ title: String?, _ subrole: String?, _ size: NSSize) -> Bool {
        // jetbrain apps sometimes generate non-windows that pass all checks in isActualWindow
        // they have no title, so we can filter them out based on that
        // we also hide windows too small
        return app.bundleIdentifier?.range(of: "^com\\.(jetbrains\\.|google\\.android\\.studio).*?$", options: .regularExpression) == nil || (
            (subrole == kAXStandardWindowSubrole || (title != nil && title != "")) &&
                size.width > 100 && size.height > 100
        )
    }

    private static func mustHaveIfColorSlurp(_ app: Application, _ subrole: String?) -> Bool {
        return app.bundleIdentifier != "com.IdeaPunch.ColorSlurp" || subrole == kAXStandardWindowSubrole
    }

    private static func iina(_ app: Application) -> Bool {
        // IINA.app can have videos float (level == 2 instead of 0)
        // there is also complex animations during which we may or may not consider the window not a window
        return app.bundleIdentifier == "com.colliderli.iina"
    }

    private static func keynote(_ app: Application) -> Bool {
        // apple Keynote has a fake fullscreen window when in presentation mode
        // it covers the screen with a AXUnknown window instead of using standard fullscreen mode
        return app.bundleIdentifier == "com.apple.iWork.Keynote"
    }

    private static func preview(_ app: Application, _ subrole: String?) -> Bool {
        // when opening multiple documents at once with apple Preview,
        // one of the window will have level == 1 for some reason
        return app.bundleIdentifier == "com.apple.Preview" && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole)
    }

    private static func openFlStudio(_ app: Application, _ title: String?) -> Bool {
        // OpenBoard is a ported app which doesn't use standard macOS windows
        return app.bundleIdentifier == "com.image-line.flstudio" && (title != nil && title != "")
    }

    private static func openBoard(_ app: Application) -> Bool {
        // OpenBoard is a ported app which doesn't use standard macOS windows
        return app.bundleIdentifier == "org.oe-f.OpenBoard"
    }

    private static func adobeAudition(_ app: Application, _ subrole: String?) -> Bool {
        // recent Adobe bundle ids gained a version/".application" suffix, so we match by prefix
        return (app.bundleIdentifier?.hasPrefix("com.adobe.Audition") ?? false) && subrole == kAXFloatingWindowSubrole
    }

    private static func adobeAfterEffects(_ app: Application, _ subrole: String?) -> Bool {
        // AE 2026's bundle id became "com.adobe.AfterEffects.application" (was "com.adobe.AfterEffects"); match by prefix
        return (app.bundleIdentifier?.hasPrefix("com.adobe.AfterEffects") ?? false) && subrole == kAXFloatingWindowSubrole
    }

    private static func adobePremierePro(_ app: Application, _ subrole: String?) -> Bool {
        return (app.bundleIdentifier?.hasPrefix("com.adobe.PremierePro") ?? false) && subrole == kAXFloatingWindowSubrole
    }

    private static func books(_ app: Application) -> Bool {
        // Books.app has animations on window creation. This means windows are originally created with subrole == AXUnknown or isOnNormalLevel == false
        return app.bundleIdentifier == "com.apple.iBooksX"
    }

    private static func worldOfWarcraft(_ app: Application, _ role: String?) -> Bool {
        return app.bundleIdentifier == "com.blizzard.worldofwarcraft" && role == kAXWindowRole
    }

    private static func battleNetBootstrapper(_ app: Application, _ role: String?) -> Bool {
        // Battlenet bootstrapper windows have subrole == AXUnknown
        return app.bundleIdentifier == "net.battle.bootstrapper" && role == kAXWindowRole
    }

    private static func drBetotte(_ app: Application) -> Bool {
        return app.bundleIdentifier == "com.ssworks.drbetotte"
    }

    private static func dvdFab(_ app: Application) -> Bool {
        return app.bundleIdentifier == "com.goland.dvdfab.macos"
    }

    private static func sanGuoShaAirWD(_ app: Application) -> Bool {
        return app.bundleIdentifier == "SanGuoShaAirWD"
    }

    private static func steam(_ app: Application, _ title: String?, _ role: String?) -> Bool {
        // All Steam windows have subrole == AXUnknown
        // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
        return app.bundleIdentifier == "com.valvesoftware.steam" && (title != nil && title != "" && role != nil)
    }

    private static func mustHaveIfSteam(_ app: Application, _ title: String?, _ role: String?) -> Bool {
        // All Steam windows have subrole == AXUnknown
        // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
        return app.bundleIdentifier != "com.valvesoftware.steam" || (title != nil && title != "" && role != nil)
    }

    private static func firefox(_ app: Application, _ role: String?, _ size: CGSize?) -> Bool {
        // Firefox fullscreen video have subrole == AXUnknown if fullscreen'ed when the base window is not fullscreen
        // Firefox tooltips are implemented as windows with subrole == AXUnknown
        return (app.bundleIdentifier?.hasPrefix("org.mozilla.firefox") ?? false) && role == kAXWindowRole && size?.height != nil && size!.height > 400
    }

    private static func vlcFullscreenVideo(_ app: Application, _ role: String?) -> Bool {
        // VLC fullscreen video have subrole == AXUnknown if fullscreen'ed
        return (app.bundleIdentifier?.hasPrefix("org.videolan.vlc") ?? false) && role == kAXWindowRole
    }

    private static func androidEmulator(_ app: Application, _ title: String?) -> Bool {
        // rescue a titled emulator window that has a non-standard subrole (so isStandardSubrole missed it).
        // empty-title emulator windows are dropped elsewhere: the side menu by the size guard, the
        // transient overlay by mustHaveIfAndroidEmulator.
        return title != "" && ApplicationDiscriminator.isAndroidEmulator(app.bundleIdentifier, app.pid)
    }

    private static func mustHaveIfAndroidEmulator(_ app: Application, _ title: String?) -> Bool {
        // The emulator spawns a transient ~device-sized AXDialog with an empty title on every focus
        // change/summon; with a standard subrole it slips past the accept gate and flickers into the
        // switcher as "qemu-system-aarch64" (#5740). The real device window always has a title
        // ("Android Emulator - <avd>:<port>"), so require a non-empty title for emulator windows.
        return !ApplicationDiscriminator.isAndroidEmulator(app.bundleIdentifier, app.pid) || (title != nil && title != "")
    }

    private static func crossoverWindow(_ app: Application, _ role: String?, _ subrole: String?, _ level: CGWindowLevel) -> Bool {
        return app.bundleIdentifier == nil && role == kAXWindowRole && subrole == kAXUnknownSubrole && level == CGWindow.normalLevel
            && (app.localizedName == "wine64-preloader" || app.executableURL?.absoluteString.contains("/winetemp-") ?? false)
    }

    private static func isAlwaysOnTopScrcpy(_ app: Application, _ level: CGWindowLevel, _ role: String?, _ subrole: String?) -> Bool {
        // scrcpy presents as a floating window when "Always on top" is enabled, so it doesn't get picked up normally.
        // It also doesn't have a bundle ID, so we need to match using the localized name, which should always be the same.
        return app.localizedName == "scrcpy" && level == CGWindow.floatingWindow && role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    private static func autocad(_ app: Application, _ subrole: String?) -> Bool {
        // AutoCAD uses the undocumented "AXDocumentWindow" subrole
        return (app.bundleIdentifier?.hasPrefix("com.autodesk.AutoCAD") ?? false) && subrole == kAXDocumentWindowSubrole
    }
}
