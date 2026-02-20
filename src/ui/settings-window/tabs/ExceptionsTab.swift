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
        dialog.beginSheetModal(for: App.app.settingsWindow) {
            if $0 == .OK, let url = dialog.url, let bundleId = Bundle(url: url)?.bundleIdentifier {
                tableView.insertRow(bundleId)
            }
        }
    }

    private static func buildRunningAppsSubmenu(_ tableView: TableView) -> NSMenu {
        let submenu = NSMenu()
        let existingIds = Set(tableView.items.map { $0.bundleIdentifier })
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !existingIds.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        for app in apps {
            guard let bundleId = app.bundleIdentifier else { continue }
            let item = NSMenuItem(title: app.localizedName ?? bundleId, action: nil, keyEquivalent: "")
            if let path = app.bundleURL?.path {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            item.representedObject = (tableView, bundleId)
            item.target = ExceptionsTab.self
            item.action = #selector(addRunningApp(_:))
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private static func addRunningApp(_ sender: NSMenuItem) {
        guard let (tableView, bundleId) = sender.representedObject as? (TableView, String) else { return }
        tableView.insertRow(bundleId)
    }
}
