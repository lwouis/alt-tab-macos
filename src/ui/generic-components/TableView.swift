import Cocoa

class BlacklistView: NSScrollView {
    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .bezelBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
        documentView = TableView(nil)
        fit(520, 360)
    }
}

class TableView: NSTableView, NSTableViewDelegate, NSTableViewDataSource {
    var items = Preferences.blacklist

    convenience init(_ dummy: Int?) {
        self.init()
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        dataSource = self
        usesAlternatingRowBackgroundColors = true
        intercellSpacing = NSSize(width: 10, height: 5)
        allowsColumnReordering = false
        allowsEmptySelection = false
        allowsMultipleSelection = true
        rowSizeStyle = .medium
        addHeaders([
            NSLocalizedString("App (BundleID starting with)", comment: ""),
            String(format: NSLocalizedString("Hide in %@", comment: "%@ is AltTab"), App.name),
            NSLocalizedString("Ignore shortcuts when active", comment: "")
        ])
        reloadData()
    }

    func addHeaders(_ columnHeaders: [String]) {
        columnHeaders.enumerated().forEach { (i, header: String) in
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col\(i + 1)"))
            column.headerToolTip = header
            column.headerCell = TableHeaderCell(header)
            if i == 0 {
                column.width = 206
            }
            addTableColumn(column)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        return tableColumn!.identifier.rawValue == "col1" ? text(item) : dropdown(item, tableColumn!.identifier.rawValue)
    }

    func text(_ item: BlacklistEntry) -> NSView {
        let text = TextField(item.bundleIdentifier)
        text.isEditable = true
        text.allowsExpansionToolTips = true
        text.drawsBackground = false
        text.isBordered = false
        text.lineBreakMode = .byTruncatingTail
        text.usesSingleLineMode = true
        text.cell!.sendsActionOnEndEditing = true
        text.onAction = { self.wasUpdated("col1", $0) }
        let parent = NSView()
        parent.addSubview(text)
        text.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        text.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }

    func dropdown(_ item: BlacklistEntry, _ colId: String) -> NSView {
        let isHidePref = colId == "col2"
        let button = NSPopUpButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.allowsExpansionToolTips = true
        button.lineBreakMode = .byTruncatingTail
        let cases: [MacroPreference] = isHidePref ? BlacklistHidePreference.allCases : BlacklistIgnorePreference.allCases
        button.addItems(withTitles: cases.map { $0.localizedString })
        button.selectItem(at: Int(isHidePref ? item.hide.rawValue : item.ignore.rawValue)!)
        button.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(button)
        button.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        button.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return parent
    }

    func wasUpdated(_ colId: String, _ control: NSControl) {
        let row = row(for: control)
        if colId == "col1" {
            items[row].bundleIdentifier = LabelAndControl.getControlValue(control, nil)!
        } else if colId == "col2" {
            items[row].hide = BlacklistHidePreference(rawValue: LabelAndControl.getControlValue(control, nil)!)!
        } else {
            items[row].ignore = BlacklistIgnorePreference(rawValue: LabelAndControl.getControlValue(control, nil)!)!
        }
        savePreferences()
    }

    func removeSelectedRows() {
        if numberOfSelectedRows > 0 {
            for selectedRowIndex in selectedRowIndexes.reversed() {
                items.remove(at: selectedRowIndex)
            }
            removeRows(at: selectedRowIndexes)
            savePreferences()
        }
    }

    func insertRow(_ bundleId: String) {
        if !(items.contains { $0.bundleIdentifier == bundleId }) {
            items.append(BlacklistEntry(bundleIdentifier: bundleId, hide: .always, ignore: .none))
            insertRows(at: [numberOfRows])
            savePreferences()
        }
    }

    func savePreferences() {
        Preferences.set("blacklist", items)
    }
}

class TableHeaderCell: NSTableHeaderCell {
    convenience init(_ textCell: String) {
        self.init(textCell: textCell)
        lineBreakMode = .byTruncatingTail
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        // add some padding so the headers can breath; get closer to what Finder does
        super.drawInterior(withFrame: cellFrame.insetBy(dx: CGFloat(5), dy: CGFloat(0)), in: controlView)
    }
}
