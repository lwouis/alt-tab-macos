import Cocoa

class PreferencesWindow: NSWindow {
    let tabViewController = TabViewController()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, styleMask: style, backing: backingStoreType, defer: flag)
        setupWindow()
        setupTabViews()
    }

    func show() {
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    @objc static func controlWasChanged(_ senderControl: NSControl) {
        let newValue = LabelAndControl.getControlValue(senderControl)
        LabelAndControl.updateControlExtras(senderControl, newValue)
        Preferences.set(senderControl.identifier!.rawValue, newValue)
        // some preferences require re-creating some components
        if ["iconSize", "fontHeight", "theme"].contains(where: { $0 == senderControl.identifier!.rawValue }) {
            (App.shared as! App).resetPreferencesDependentComponents()
        }
    }

    private func setupWindow() {
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
    }

    private func setupTabViews() {
        contentViewController = tabViewController
        tabViewController.tabStyle = .toolbar
        tabViewController.addTabViewItem(GeneralTab.make())
        tabViewController.addTabViewItem(AppearanceTab.make())
        tabViewController.addTabViewItem(UpdatesTab.make())
        tabViewController.addTabViewItem(AboutTab.make())
    }
}
