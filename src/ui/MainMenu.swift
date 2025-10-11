class MainMenu {
    private static var mainMenu: NSMenu!

    /// classic keyboard shortcuts like copy-and-paste are missing without a MainMenu. We generated the default menu from XCode and load it
    /// see https://stackoverflow.com/a/3746058/2249756
    static func loadFromXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        mainMenu = menuObjects?.first { $0 is NSMenu } as? NSMenu
        App.shared.mainMenu = mainMenu
    }

    /// we toggle the mainMenu off when showing the main window, and on when showing secondary windows
    static func toggle(enabled: Bool) {
        if enabled {
            if App.shared.mainMenu == nil {
                App.shared.mainMenu = mainMenu
            }
        } else {
            App.shared.mainMenu = nil
        }
    }
}
