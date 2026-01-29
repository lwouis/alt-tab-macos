class MainMenu {
    private static var mainMenu: NSMenu!
    private static var menuItemsWithShortcut = [NSMenuItem: String]()

    /// classic keyboard shortcuts like copy-and-paste are missing without a MainMenu. We generated the default menu from XCode and load it
    /// see https://stackoverflow.com/a/3746058/2249756
    static func loadFromXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        mainMenu = menuObjects?.first { $0 is NSMenu } as? NSMenu
        App.shared.mainMenu = mainMenu
        rememberMenuItemsWithShortcut()
    }

    static func toggle(enabled: Bool) {
        for (item, keyEquivalent) in menuItemsWithShortcut {
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
    }

    private static func rememberMenuItemsWithShortcut() {
        var stack: [NSMenu] = [mainMenu]
        while let menu = stack.popLast() {
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    menuItemsWithShortcut[item] = item.keyEquivalent
                }
                if let submenu = item.submenu {
                    stack.append(submenu)
                }
            }
        }
    }
}
