import Cocoa

class StatusItem {
    static func make(_ app: App) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button!.title = App.name
        item.menu = NSMenu()
        item.menu!.addItem(
                withTitle: "Show",
                action: #selector(app.showUi),
                keyEquivalent: "s"
        )
        item.menu!.addItem(
                withTitle: "Preferences…",
                action: #selector(app.showPreferencesPanel),
                keyEquivalent: ",")
        item.menu!.addItem(
            withTitle: "Quit \(App.name) #VERSION#",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
        return item
    }
}
