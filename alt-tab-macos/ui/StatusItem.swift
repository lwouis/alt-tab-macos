import Cocoa

class StatusItem {
    static func make(_ application: Application) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button!.title = Application.name
        item.menu = NSMenu()
        item.menu!.addItem(
                withTitle: "Show",
                action: #selector(application.showUi),
                keyEquivalent: "s"
        )
        item.menu!.addItem(
                withTitle: "Preferences…",
                action: #selector(application.showPreferencesPanel),
                keyEquivalent: ",")
        item.menu!.addItem(
            withTitle: "Quit \(Application.name) #VERSION#",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
        return item
    }
}
