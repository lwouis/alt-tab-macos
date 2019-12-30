import Cocoa

class StatusItem {
    static func make(_ application: Application) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage.init(named: "icon.icns")
        image?.isTemplate = true
        item.button!.image = image
        item.button!.imageScaling = NSImageScaling.scaleProportionallyUpOrDown
        item.menu = NSMenu()
        item.menu!.addItem(
                withTitle: "Version #VERSION#",
                action: nil,
                keyEquivalent: "")
        item.menu!.addItem(
                withTitle: "Preferences…",
                action: #selector(application.showPreferencesPanel),
                keyEquivalent: ",")
        item.menu!.addItem(
                withTitle: "Quit \(ProcessInfo.processInfo.processName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
        return item
    }
}
