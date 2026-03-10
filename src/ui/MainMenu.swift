class MainMenu {
    private static var mainMenu: NSMenu!
    private static var menuItemsWithShortcut = [NSMenuItem: String]()
    private static var editMenuItems = Set<NSMenuItem>()

    /// classic keyboard shortcuts like copy-and-paste are missing without a MainMenu. We generated the default menu from XCode and load it
    /// see https://stackoverflow.com/a/3746058/2249756
    static func loadFromXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        mainMenu = menuObjects?.first { $0 is NSMenu } as? NSMenu
        App.shared.mainMenu = mainMenu
        rememberMenuItemsWithShortcut()
    }

    static func toggle(_ enabled: Bool) {
        for (item, keyEquivalent) in menuItemsWithShortcut {
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
    }

    static func toggleEditMenu(_ enabled: Bool) {
        for item in editMenuItems {
            guard let keyEquivalent = menuItemsWithShortcut[item] else { continue }
            item.keyEquivalent = enabled ? keyEquivalent : ""
        }
    }

    private static func rememberMenuItemsWithShortcut() {
        guard let items = mainMenu?.items else { return }
        let editSubmenu = items.first { $0.submenu?.title == "Edit" }?.submenu
        var stack: [(NSMenu, Bool)] = [(mainMenu, false)]
        while let (menu, isEdit) = stack.popLast() {
            let isEditMenu = isEdit || menu === editSubmenu
            for item in menu.items {
                if !item.keyEquivalent.isEmpty {
                    menuItemsWithShortcut[item] = item.keyEquivalent
                    if isEditMenu { editMenuItems.insert(item) }
                }
                if let submenu = item.submenu {
                    stack.append((submenu, isEditMenu))
                }
            }
        }
    }
}
