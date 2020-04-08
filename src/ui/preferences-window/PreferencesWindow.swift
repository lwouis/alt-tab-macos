import Cocoa

class PreferencesWindow: NSWindow {
    let tabViewController = TabViewController()

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false, screen: NSScreen.main)
        setupWindow()
        setupTabViews()
    }

    private func setupWindow() {
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    private func setupTabViews() {
        contentViewController = tabViewController
        tabViewController.tabStyle = .toolbar
        tabViewController.addTabViewItem(GeneralTab.make())
        tabViewController.addTabViewItem(AppearanceTab.make())
        tabViewController.addTabViewItem(UpdatesTab.make())
        tabViewController.addTabViewItem(AboutTab.make())
    }

    func show() {
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    static func controlWasChanged(_ senderControl: NSControl) {
        let newValue = LabelAndControl.getControlValue(senderControl)
        LabelAndControl.updateControlExtras(senderControl, newValue)
        Preferences.set(senderControl.identifier!.rawValue, newValue)
        // some preferences require re-creating some components
        if ["iconSize", "fontHeight", "theme"].contains(where: { $0 == senderControl.identifier!.rawValue }) {
            (App.shared as! App).resetPreferencesDependentComponents()
        }
    }
}
