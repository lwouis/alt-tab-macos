import Cocoa

class StatusItem {
    static func make(_ application: Application) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button!.title = Application.name
        item.menu = NSMenu()
        item.menu!.addItem(
                withTitle: "Version #VERSION#",
                action: nil,
                keyEquivalent: "")
        item.menu!.addItem(
                withTitle: "Preferences…",
                action: #selector(application.showCenteredPreferencesPanel),
                keyEquivalent: ",")
        item.menu!.addItem(
                withTitle: "Quit \(ProcessInfo.processInfo.processName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
        return item
    }
}
