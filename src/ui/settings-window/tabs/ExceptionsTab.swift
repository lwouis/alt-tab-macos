import Cocoa

class ExceptionsTab {
    static func initTab() -> NSView {
        let exceptions = ExceptionsView(width: SettingsWindow.contentWidth - 2 * TableGroupView.padding)
        let tableView = exceptions.documentView as! TableView
        let addButton = makeAddButton(tableView)
        let removeButton = makeRemoveButton(tableView)
        let buttonsStack = NSStackView(views: [addButton, removeButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 2
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        _ = table.addRow(leftViews: [exceptions], secondaryViews: [buttonsStack])
        let view = TableGroupSetView(originalViews: [table], bottomPadding: 0)
        return view
    }

    private static func makeAddButton(_ tableView: TableView) -> NSButton {
        let button = makeCircleButton(systemSymbolName: "plus")
        button.onAction = { [weak tableView] _ in
            guard let tableView else { return }
            showAddMenu(tableView, sender: button)
        }
        return button
    }

    private static func makeRemoveButton(_ tableView: TableView) -> NSButton {
        let button = makeCircleButton(systemSymbolName: "minus")
        button.onAction = { [weak tableView] _ in
            tableView?.removeSelectedRows()
        }
        return button
    }

    private static func makeCircleButton(systemSymbolName: String) -> NSButton {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = true
        button.bezelStyle = .circular
        button.showsBorderOnlyWhileMouseInside = false
        if #available(macOS 11.0, *) {
            button.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: nil)
        } else {
            let templateName = systemSymbolName == "plus" ? NSImage.addTemplateName : NSImage.removeTemplateName
            button.image = NSImage(named: templateName)
        }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private static func showAddMenu(_ tableView: TableView, sender: NSButton) {
        let menu = NSMenu()
        let runningAppsItem = NSMenuItem(title: NSLocalizedString("Add a running app", comment: ""), action: nil, keyEquivalent: "")
        runningAppsItem.submenu = buildRunningAppsSubmenu(tableView)
        menu.addItem(runningAppsItem)
        let diskItem = NSMenuItem(title: NSLocalizedString("Add an app from disk", comment: ""), action: nil, keyEquivalent: "")
        diskItem.representedObject = tableView
        diskItem.target = ExceptionsTab.self
        diskItem.action = #selector(addFromDisk(_:))
        menu.addItem(diskItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private static func addFromDisk(_ sender: NSMenuItem) {
        guard let tableView = sender.representedObject as? TableView else { return }
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = false
        dialog.allowedFileTypes = ["app"]
        dialog.canChooseDirectories = false
        dialog.beginSheetModal(for: SettingsWindow.shared) {
            if $0 == .OK, let url = dialog.url, let bundleId = Bundle(url: url)?.bundleIdentifier {
                tableView.insertRow(bundleId)
            }
        }
    }

    private static func buildRunningAppsSubmenu(_ tableView: TableView) -> NSMenu {
        let submenu = NSMenu()
        runningAppsForMenu(tableView).forEach { submenu.addItem(makeRunningAppItem(tableView, $0.app, $0.bundleId)) }
        return submenu
    }

    private static func runningAppsForMenu(_ tableView: TableView) -> [(app: NSRunningApplication, bundleId: String)] {
        let existingIds = Set(tableView.items.map { $0.bundleIdentifier })
        var appsByBundleId = [String: NSRunningApplication]()
        runningAppCandidates().forEach {
            guard let bundleId = $0.bundleIdentifier, !existingIds.contains(bundleId), appsByBundleId[bundleId] == nil else { return }
            appsByBundleId[bundleId] = $0
        }
        return appsByBundleId.map { ($0.value, $0.key) }.sorted { appMenuTitle($0.app).localizedStandardCompare(appMenuTitle($1.app)) == .orderedAscending }
    }

    private static func runningAppCandidates() -> [NSRunningApplication] {
        windowBackedRunningApps() + regularRunningApps()
    }

    private static func windowBackedRunningApps() -> [NSRunningApplication] {
        Windows.list.map { $0.application.runningApplication }
    }

    private static func regularRunningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private static func makeRunningAppItem(_ tableView: TableView, _ app: NSRunningApplication, _ bundleId: String) -> NSMenuItem {
        let item = NSMenuItem(title: appMenuTitle(app), action: nil, keyEquivalent: "")
        if let path = app.bundleURL?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        item.representedObject = (tableView, bundleId)
        item.target = ExceptionsTab.self
        item.action = #selector(addRunningApp(_:))
        return item
    }

    private static func appMenuTitle(_ app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? ""
    }

    @objc private static func addRunningApp(_ sender: NSMenuItem) {
        guard let (tableView, bundleId) = sender.representedObject as? (TableView, String) else { return }
        tableView.insertRow(bundleId)
    }
}

class ExceptionsView: ForwardingVerticalScrollView {
    convenience init(width: CGFloat = 500, height: CGFloat = 378) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        verticalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        documentView = TableView(nil)
        fit(width, height)
        wantsLayer = true
        layer!.cornerRadius = TableGroupView.cornerRadius
        layer!.masksToBounds = true
        contentView.wantsLayer = true
        contentView.layer!.cornerRadius = TableGroupView.cornerRadius
        contentView.layer!.masksToBounds = true
    }
}
