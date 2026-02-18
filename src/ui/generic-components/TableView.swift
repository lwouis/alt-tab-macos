import Cocoa

class BlacklistView: NSScrollView {
    convenience init(width: CGFloat = 500, height: CGFloat = 378) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = true
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

    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        axis == .vertical
    }

    override func scrollWheel(with event: NSEvent) {
        let before = contentView.bounds.origin
        super.scrollWheel(with: event)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shouldForwardToParent(event, before) else { return }
            self.parentScrollView()?.scrollWheel(with: event)
        }
    }

    private func shouldForwardToParent(_ event: NSEvent, _ before: CGPoint) -> Bool {
        guard isVerticalScroll(event) else { return false }
        guard abs(contentView.bounds.origin.y - before.y) < 0.01 else { return false }
        return isAtVerticalBoundary(event)
    }

    private func isVerticalScroll(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) && abs(event.scrollingDeltaY) > 0.1
    }

    private func isAtVerticalBoundary(_ event: NSEvent) -> Bool {
        guard let content = documentView else { return false }
        let visible = contentView.documentVisibleRect
        let dy = normalizedVerticalDelta(event)
        if dy > 0 { return visible.minY <= content.bounds.minY + 0.5 }
        if dy < 0 { return visible.maxY >= content.bounds.maxY - 0.5 }
        return false
    }

    private func normalizedVerticalDelta(_ event: NSEvent) -> CGFloat {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        return event.isDirectionInvertedFromDevice ? -delta : delta
    }

    private func parentScrollView() -> NSScrollView? {
        var parent = superview
        while let view = parent {
            if let scrollView = view as? NSScrollView { return scrollView }
            parent = view.superview
        }
        return nil
    }
}

class TableView: NSTableView {
    var items = Preferences.blacklist

    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        axis == .vertical
    }

    convenience init(_: Int?) {
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

    func insertRow(_ bundleId: String) {
        if !(items.contains { $0.bundleIdentifier == bundleId }) {
            items.append(BlacklistEntry(bundleIdentifier: bundleId, hide: .always, ignore: .none))
            insertRows(at: [numberOfRows])
            savePreferences()
        }
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

    private func addHeaders(_ columnHeaders: [String]) {
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

    private func wasUpdated(_ colId: String, _ control: NSControl) {
        let row = row(for: control)
        if colId == "col1" {
            items[row].bundleIdentifier = LabelAndControl.getControlValue(control, nil)!
        } else if colId == "col2" {
            items[row].hide = BlacklistHidePreference.allCases[Int(LabelAndControl.getControlValue(control, nil)!)!]
        } else {
            items[row].ignore = BlacklistIgnorePreference.allCases[Int(LabelAndControl.getControlValue(control, nil)!)!]
        }
        savePreferences()
    }

    private func savePreferences() {
        Preferences.set("blacklist", items)
    }

    private func text(_ item: BlacklistEntry) -> NSView {
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

    private func dropdown(_ item: BlacklistEntry, _ colId: String) -> NSView {
        let isHidePref = colId == "col2"
        let button = NSPopUpButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.allowsExpansionToolTips = true
        button.lineBreakMode = .byTruncatingTail
        let cell = button.cell as! NSPopUpButtonCell
        cell.bezelStyle = .regularSquare
        cell.arrowPosition = .arrowAtBottom
        cell.imagePosition = .imageOverlaps
        let cases: [MacroPreference] = isHidePref ? BlacklistHidePreference.allCases : BlacklistIgnorePreference.allCases
        button.addItems(withTitles: cases.map { $0.localizedString })
        button.selectItem(at: isHidePref ? item.hide.index : item.ignore.index)
        button.onAction = { self.wasUpdated(colId, $0) }
        let parent = NSView()
        parent.addSubview(button)
        button.leadingAnchor.constraint(equalTo: parent.leadingAnchor).isActive = true
        button.centerYAnchor.constraint(equalTo: parent.centerYAnchor).isActive = true
        button.widthAnchor.constraint(lessThanOrEqualTo: parent.widthAnchor).isActive = true
        return parent
    }
}

extension TableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}

extension TableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        return tableColumn!.identifier.rawValue == "col1" ? text(item) : dropdown(item, tableColumn!.identifier.rawValue)
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
