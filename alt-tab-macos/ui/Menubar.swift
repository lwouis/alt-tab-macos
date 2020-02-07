import Cocoa

class Menubar {
    static func make(_ app: App) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button!.title = "AltTab"
        item.menu = NSMenu()
        item.menu!.addItem(
                withTitle: NSLocalizedString("Show", comment: ""),
                action: #selector(app.showUi),
                keyEquivalent: "s"
        )
        item.menu!.addItem(
                withTitle: NSLocalizedString("Preferences…", comment: ""),
                action: #selector(app.showPreferencesPanel),
                keyEquivalent: ",")
        item.menu!.addItem(
                withTitle: NSLocalizedString("Send feedback…", comment: ""),
                action: #selector(app.showFeedbackPanel),
                keyEquivalent: ",")
        item.menu!.addItem(NSMenuItem.separator())
        item.menu!.addItem(
            withTitle: NSLocalizedString("Quit", comment: "") + " " + App.name,
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
        return item
    }
}
