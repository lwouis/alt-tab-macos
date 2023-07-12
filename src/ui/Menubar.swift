import Cocoa

class Menubar {
    var statusItem: NSStatusItem!
    var menu: NSMenu!

    init() {
        menu = NSMenu()
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        menu.addItem(
            withTitle: String(format: NSLocalizedString("About %@", comment: "Menubar option. %@ is AltTab"), App.name),
            action: #selector(App.app.showAboutTab),
            keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: NSLocalizedString("Show", comment: "Menubar option"),
            action: #selector(App.app.showUi),
            keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Preferences…", comment: "Menubar option"),
            action: #selector(App.app.showPreferencesWindow),
            keyEquivalent: ",")
        menu.addItem(
            withTitle: NSLocalizedString("Check for updates…", comment: "Menubar option"),
            action: #selector(App.app.checkForUpdatesNow),
            keyEquivalent: "")
        menu.addItem(
            withTitle: NSLocalizedString("Send feedback…", comment: "Menubar option"),
            action: #selector(App.app.showFeedbackPanel),
            keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: String(format: NSLocalizedString("Quit %@", comment: "Menubar option. %@ is AltTab"), App.name),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.target = self
        statusItem.button!.action = #selector(statusItemOnClick)
        statusItem.button!.sendAction(on: [.leftMouseDown, .rightMouseDown])
        menubarIconCallback(nil)
    }

    @objc func statusItemOnClick() {
        if NSApp.currentEvent!.type == .leftMouseDown {
            statusItem.popUpMenu(App.app.menubar.menu)
        } else {
            App.app.showUi()
        }
    }

    func menubarIconCallback(_ sender: NSControl?) {
        if Preferences.menubarIcon == .hidden {
            statusItem.isVisible = false
        } else {
            loadPreferredIcon()
        }
    }

    private func loadPreferredIcon() {
        let i = imageIndexFromPreference()
        let image = NSImage(named: "menubar-" + i)!
        image.isTemplate = i == "3" ? false : true
        statusItem.button!.image = image
        statusItem.isVisible = true
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
    }

    private func imageIndexFromPreference() -> String {
        switch Preferences.menubarIcon {
            case .outlined: return "1"
            case .filled: return "2"
            case .colored: return "3"
            default: return "4"
        }
    }
}