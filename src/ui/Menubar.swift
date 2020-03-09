import Cocoa

class Menubar {
    static func make(_ app: App) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(named: "menubar-icon")
        image!.isTemplate = true
        item.button!.image = image
        item.button!.imageScaling = .scaleProportionallyUpOrDown
        item.menu = NSMenu()
        item.menu!.addItem(
                withTitle: NSLocalizedString("Show", comment: ""),
                action: #selector(app.showUi),
                keyEquivalent: ""
        )
        item.menu!.addItem(
                withTitle: NSLocalizedString("Preferences…", comment: ""),
                action: #selector(app.showPreferencesPanel),
                keyEquivalent: ",")
        item.menu!.addItem(
                withTitle: NSLocalizedString("Check for updates…", comment: ""),
                action: #selector(app.checkForUpdatesNow),
                keyEquivalent: "")
        item.menu!.addItem(
                withTitle: NSLocalizedString("Send feedback…", comment: ""),
                action: #selector(app.showFeedbackPanel),
                keyEquivalent: "")
        item.menu!.addItem(NSMenuItem.separator())
        item.menu!.addItem(
            withTitle: NSLocalizedString("Quit", comment: "") + " " + App.name,
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
        return item
    }
}
