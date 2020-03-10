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
        (App.shared as! App).initPreferencesDependentComponents()
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
