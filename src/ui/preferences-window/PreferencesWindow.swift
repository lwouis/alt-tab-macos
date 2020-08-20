import Cocoa

class PreferencesWindow: NSWindow, NSToolbarDelegate {
    var toolbarItems = [NSToolbarItem.Identifier: (Int, NSToolbarItem, NSView)]()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, styleMask: style, backing: backingStoreType, defer: flag)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        styleMask.insert([.miniaturizable, .closable])
        addQuitButton()
    }

    private func addQuitButton() {
        let quitButton = NSButton(title: NSLocalizedString("Quit", comment: ""), target: nil, action: #selector(NSApplication.terminate(_:)))
        let titleBarView = standardWindowButton(.closeButton)!.superview!
        titleBarView.addSubview(quitButton)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.topAnchor.constraint(equalTo: titleBarView.topAnchor, constant: 5).isActive = true
        quitButton.rightAnchor.constraint(equalTo: titleBarView.rightAnchor, constant: -8).isActive = true
    }

    private func setupView() {
        toolbar = NSToolbar(identifier: "1")
        toolbar!.delegate = self
        toolbar!.displayMode = .iconAndLabel
        toolbar!.showsBaselineSeparator = true
        [
            (0, NSLocalizedString("General", comment: ""), "general", GeneralTab.initTab()),
            (1, NSLocalizedString("Controls", comment: ""), "controls", ControlsTab.initTab()),
            (2, NSLocalizedString("Appearance", comment: ""), "appearance", AppearanceTab.initTab()),
            (3, NSLocalizedString("Policies", comment: ""), "policies", PoliciesTab.initTab()),
            (4, NSLocalizedString("Blacklists", comment: ""), "blacklists", BlacklistsTab.initTab()),
            (5, NSLocalizedString("About", comment: ""), "about", AboutTab.initTab()),
            (6, NSLocalizedString("Acknowledgments", comment: ""), "acknowledgments", AcknowledgmentsTab.initTab()),
        ]
            .forEach { makeToolbarItem($0.0, $0.1, $0.2, $0.3) }

        let largestTabWidth = Array(toolbarItems.values).reduce(CGFloat(0)) { max($0, $1.2.subviews[0].fittingSize.width) }
        Array(toolbarItems.values).forEach {
            $0.2.fit(largestTabWidth, $0.2.subviews[0].fittingSize.height)
        }
        toolbar!.selectedItemIdentifier = Array(toolbarItems).first { (k, v) in v.0 == 0 }!.key
        tabItemClicked(toolbarItems[toolbar!.selectedItemIdentifier!]!.1)
    }

    func makeToolbarItem(_ index: Int, _ label: String, _ image: String, _ view: NSView) {
        let id = NSToolbarItem.Identifier(rawValue: image)
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.image = NSImage.initTemplateCopy(image)
        item.target = self
        item.action = #selector(tabItemClicked)
        let wrapView = NSView(frame: .zero)
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.subviews = [view]
        view.centerXAnchor.constraint(equalTo: wrapView.centerXAnchor).isActive = true
        toolbarItems[id] = (index, item, wrapView)
        toolbar!.insertItem(withItemIdentifier: id, at: index)
    }

    @objc func tabItemClicked(_ item: NSToolbarItem) {
        let item = toolbarItems[item.itemIdentifier]!
        contentView = item.2
        title = item.1.label
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        return toolbarItems[itemIdentifier]!.1
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return Array(toolbarItems.keys)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return Array(toolbarItems.keys)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return Array(toolbarItems.keys)
    }
}
