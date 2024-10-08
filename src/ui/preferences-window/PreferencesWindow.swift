import Cocoa

class PreferencesWindow: NSWindow, NSToolbarDelegate {
    static let width = CGFloat(520)

    var toolbarItems = [NSToolbarItem.Identifier: (Int, NSToolbarItem, NSView)]()
    var canBecomeKey_ = true
    override var canBecomeKey: Bool { canBecomeKey_ }
    var largestTabWidth: CGFloat!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .miniaturizable, .closable], backing: .buffered, defer: false)
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        addQuitButton()
    }

    private func addQuitButton() {
        let quitButton = NSButton(title: NSLocalizedString("Quit", comment: ""), target: nil, action: #selector(NSApplication.terminate(_:)))
        let titleBarView = standardWindowButton(.closeButton)!.superview!
        titleBarView.addSubview(quitButton)
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.topAnchor.constraint(equalTo: titleBarView.topAnchor, constant: 5).isActive = true
        if windowTitlebarLayoutDirection == .rightToLeft {
            quitButton.leftAnchor.constraint(equalTo: titleBarView.leftAnchor, constant: 8).isActive = true
        } else {
            quitButton.rightAnchor.constraint(equalTo: titleBarView.rightAnchor, constant: -8).isActive = true
        }
    }

    private func setupView() {
        toolbar = NSToolbar(identifier: "1")
        toolbar!.delegate = self
        // toolbar breaks with the new default style on macOS 11; we force the classic style (see #914)
        if #available(macOS 11.0, *) { toolbarStyle = .preference }
        toolbar!.displayMode = .iconAndLabel
        toolbar!.showsBaselineSeparator = true
        [
            (0, NSLocalizedString("General", comment: ""), "general", "switch.2", GeneralTab.initTab()),
            (1, NSLocalizedString("Controls", comment: ""), "controls", "command", ControlsTab.initTab()),
            (2, NSLocalizedString("Appearance", comment: ""), "appearance", "paintpalette", AppearanceTab.initTab()),
            (3, NSLocalizedString("Policies", comment: ""), "policies", "antenna.radiowaves.left.and.right", PoliciesTab.initTab()),
            (4, NSLocalizedString("Blacklists", comment: ""), "blacklists", "hand.raised", BlacklistsTab.initTab()),
            (5, NSLocalizedString("About", comment: ""), "about", "info.circle", AboutTab.initTab()),
            (6, NSLocalizedString("Acknowledgments", comment: ""), "acknowledgments", "hand.thumbsup", AcknowledgmentsTab.initTab()),
        ].forEach { makeToolbarItem($0.0, $0.1, $0.2, $0.3, $0.4) }

        largestTabWidth = Array(toolbarItems.values).reduce(CGFloat(0)) { max($0, $1.2.subviews[0].fittingSize.width) }
        Array(toolbarItems.values).forEach {
            $0.2.fit(largestTabWidth, $0.2.subviews[0].fittingSize.height)
        }
        selectTab("general")
    }

    func selectTab(_ id: String) {
        toolbar!.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: id)
        tabItemClicked(toolbarItems[toolbar!.selectedItemIdentifier!]!.1)
    }

    func makeToolbarItem(_ index: Int, _ label: String, _ id: String, _ image: String, _ view: NSView) {
        let identifier = NSToolbarItem.Identifier(rawValue: id)
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        if #available(macOS 11.0, *) {
            item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        } else {
            item.image = NSImage.initTemplateCopy(image)
            item.maxSize = .init(width: 22, height: 22)
        }
        item.target = self
        item.action = #selector(tabItemClicked)
        let wrapView = NSView(frame: .zero)
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.subviews = [view]
        view.centerXAnchor.constraint(equalTo: wrapView.centerXAnchor).isActive = true
        toolbarItems[identifier] = (index, item, wrapView)
        toolbar!.insertItem(withItemIdentifier: identifier, at: index)
    }

    @objc func tabItemClicked(_ item: NSToolbarItem) {
        let item = toolbarItems[item.itemIdentifier]!
        contentView = item.2
        title = item.1.label

        // Reset focused ring
        makeFirstResponder(contentView?.subviews[0])
        recalculateKeyViewLoop()
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

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}
