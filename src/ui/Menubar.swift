import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!

    static func initialize() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
        statusItem.menu = NSMenu()
        statusItem.menu!.addItem(
            withTitle: NSLocalizedString("Show", comment: "Menubar option"),
            action: #selector(App.app.showUi),
            keyEquivalent: "")
        statusItem.menu!.addItem(
            withTitle: NSLocalizedString("Preferences…", comment: "Menubar option"),
            action: #selector(App.app.showPreferencesPanel),
            keyEquivalent: ",")
        statusItem.menu!.addItem(
            withTitle: NSLocalizedString("Check for updates…", comment: "Menubar option"),
            action: #selector(App.app.checkForUpdatesNow),
            keyEquivalent: "")
        statusItem.menu!.addItem(
            withTitle: NSLocalizedString("Send feedback…", comment: "Menubar option"),
            action: #selector(App.app.showFeedbackPanel),
            keyEquivalent: "")
        statusItem.menu!.addItem(NSMenuItem.separator())
        statusItem.menu!.addItem(
            withTitle: String(format: NSLocalizedString("Quit %@", comment: "Menubar option. %@ is AltTab"), App.name),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menubarIconCallback(nil)
    }

    static func menubarIconCallback(_ sender: NSControl?) {
        if Preferences.menubarIcon == .hidden {
            statusItem.isVisible = false
        } else {
            loadPreferredIcon()
        }
    }

    static private func loadPreferredIcon() {
        let i = imageIndexFromPreference()
        let image = NSImage(named: "menubar-icon-" + i)!
        image.isTemplate = i == "3" ? false : true
        statusItem.button!.appearance = i == "3" ? NSAppearance(named: .aqua) : nil
        statusItem.button!.image = image
        statusItem.isVisible = true
    }

    static private func imageIndexFromPreference() -> String {
        switch Preferences.menubarIcon {
            case .outlined: return "1"
            case .filled: return "2"
            case .colored: return "3"
            default: return "4"
        }
    }
}