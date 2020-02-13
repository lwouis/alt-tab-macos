import Cocoa

class PreferencesWindow: NSWindow {
    let tabViewController = TabViewController()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, styleMask: style, backing: backingStoreType, defer: flag)
        LabelAndControl.callbackTarget = self
        setupWindow()
        setupTabViews()
    }

    func show() {
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func controlWasChanged(_ senderControl: NSControl) {
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
        tabViewController.addTabViewItem(ShortcutsTab.make())
        tabViewController.addTabViewItem(AppearanceTab.make())
        tabViewController.addTabViewItem(UpdatesTab.make())
        tabViewController.addTabViewItem(AboutTab.make())
    }
}
