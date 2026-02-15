import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

private class ShortcutSidebarRow: ClickHoverStackView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let chevronLabel = NSTextField(labelWithString: "›")
    private let textColumn = NSStackView()
    private var isSelectedRow = false
    private var isHoveredRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = TableGroupView.cornerRadius
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 0
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        titleLabel.alignment = .left
        summaryLabel.alignment = .left
        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        chevronLabel.font = NSFont.systemFont(ofSize: 22)
        chevronLabel.textColor = .secondaryLabelColor
        textColumn.addArrangedSubview(titleLabel)
        textColumn.addArrangedSubview(summaryLabel)
        addArrangedSubview(textColumn)
        addArrangedSubview(spacer)
        addArrangedSubview(chevronLabel)
        textColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TableGroupView.padding).isActive = true
        textColumn.trailingAnchor.constraint(lessThanOrEqualTo: chevronLabel.leadingAnchor, constant: -8).isActive = true
        chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TableGroupView.padding).isActive = true
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func setContent(_ title: String, _ summary: String) {
        titleLabel.stringValue = title
        summaryLabel.stringValue = summary
    }

    func setSelected(_ selected: Bool) {
        isSelectedRow = selected
        updateStyle()
    }

    func setHovered(_ hovered: Bool) {
        isHoveredRow = hovered
        updateStyle()
    }

    private func updateStyle() {
        let selectedColor = NSColor.systemAccentColor.withAlphaComponent(0.16)
        let backgroundColor = isSelectedRow ? selectedColor : (isHoveredRow ? NSColor.tableHoverColor : .clear)
        let titleFont = NSFont.systemFont(ofSize: 13, weight: isSelectedRow ? .semibold : .regular)
        titleLabel.attributedStringValue = NSAttributedString(string: titleLabel.stringValue, attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor])
        layer?.backgroundColor = backgroundColor.cgColor
    }
}

private class ControlsSidebarScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard shouldHandleVerticalScroll(event) else {
            super.scrollWheel(with: event)
            return
        }
        if canScrollInEventDirection(event) {
            super.scrollWheel(with: event)
        } else {
            parentScrollView()?.scrollWheel(with: event)
        }
    }

    private func shouldHandleVerticalScroll(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) && abs(event.scrollingDeltaY) > 0.1
    }

    private func canScrollInEventDirection(_ event: NSEvent) -> Bool {
        let maxOffset = maxVerticalOffset()
        guard maxOffset > 0 else { return false }
        let y = contentView.bounds.origin.y
        let dy = normalizedVerticalDelta(event)
        if dy > 0 {
            return y > 0.5
        }
        if dy < 0 {
            return y < maxOffset - 0.5
        }
        return false
    }

    private func maxVerticalOffset() -> CGFloat {
        guard let content = documentView?.subviews.first else { return 0 }
        return max(0, content.fittingSize.height - contentView.bounds.height)
    }

    private func normalizedVerticalDelta(_ event: NSEvent) -> CGFloat {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        return event.isDirectionInvertedFromDevice ? -delta : delta
    }

    private func parentScrollView() -> NSScrollView? {
        var parent = superview
        while let view = parent {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            parent = view.superview
        }
        return nil
    }
}

class ControlsTab {
    static var shortcuts = [String: ATShortcut]()
    static var shortcutControls = [String: (CustomRecorderControl, String)]()
    static var shortcutsActions = [
        "holdShortcut": { App.app.focusTarget() },
        "holdShortcut2": { App.app.focusTarget() },
        "holdShortcut3": { App.app.focusTarget() },
        "focusWindowShortcut": { App.app.focusTarget() },
        "nextWindowShortcut": { App.app.showUiOrCycleSelection(0, false) },
        "nextWindowShortcut2": { App.app.showUiOrCycleSelection(1, false) },
        "nextWindowShortcut3": { App.app.showUiOrCycleSelection(2, false) },
        "previousWindowShortcut": { App.app.previousWindowShortcutWithRepeatingKey() },
        "→": { App.app.cycleSelection(.right) },
        "←": { App.app.cycleSelection(.left) },
        "↑": { App.app.cycleSelection(.up) },
        "↓": { App.app.cycleSelection(.down) },
        "vimCycleRight": { App.app.cycleSelection(.right) },
        "vimCycleLeft": { App.app.cycleSelection(.left) },
        "vimCycleUp": { App.app.cycleSelection(.up) },
        "vimCycleDown": { App.app.cycleSelection(.down) },
        "cancelShortcut": { App.app.cancelSearchModeOrHideUi() },
        "closeWindowShortcut": { App.app.closeSelectedWindow() },
        "minDeminWindowShortcut": { App.app.minDeminSelectedWindow() },
        "toggleFullscreenWindowShortcut": { App.app.toggleFullscreenSelectedWindow() },
        "quitAppShortcut": { App.app.quitSelectedApp() },
        "hideShowAppShortcut": { App.app.hideShowSelectedApp() },
        "searchShortcut": { App.app.toggleSearchMode() },
        "lockSearchShortcut": { App.app.lockSearchMode() },
    ]
    static var arrowKeysCheckbox: Switch!
    static var vimKeysCheckbox: Switch!

    static var shortcutsWhenActiveSheet: ShortcutsWhenActiveSheet!
    static var additionalControlsSheet: AdditionalControlsSheet!

    private static let shortcutSidebarWidth = CGFloat(200)
    private static let sidebarRowHeight = CGFloat(52)
    private static var shortcutEditorWidth: CGFloat { SettingsWindow.contentWidth - shortcutSidebarWidth - 1 }
    private static let gestureSelectionIndex = -1
    private static let staticManagedShortcutPreferences = [
        "focusWindowShortcut", "previousWindowShortcut", "cancelShortcut", "searchShortcut", "lockSearchShortcut",
        "closeWindowShortcut", "minDeminWindowShortcut", "toggleFullscreenWindowShortcut", "quitAppShortcut", "hideShowAppShortcut",
    ]
    private static let removableShortcutPreferences = [
        "holdShortcut", "nextWindowShortcut",
        "appsToShow", "spacesToShow", "screensToShow",
        "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows", "showWindowlessApps",
        "windowOrder", "shortcutStyle",
    ]
    private static let shortcutDropdownPreferences = [
        "appsToShow", "spacesToShow", "screensToShow",
        "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows", "showWindowlessApps",
        "windowOrder",
    ]
    private static let arrowKeys = ["←", "→", "↑", "↓"]
    private static let vimKeyActions = [
        "h": "vimCycleLeft",
        "l": "vimCycleRight",
        "k": "vimCycleUp",
        "j": "vimCycleDown",
    ]

    private static var selectedShortcutIndex = 0
    private static var shortcutRowsStackView: NSStackView?
    private static var shortcutRows = [ShortcutSidebarRow]()
    private static var shortcutEditorViews = [TableGroupView]()
    private static var gestureSidebarRow: ShortcutSidebarRow?
    private static var gestureEditorView: TableGroupView?
    private static var shortcutCountButtons: NSSegmentedControl?

    static func initializePreferencesDependentState() {
        applyActiveShortcutPreferences()
        staticManagedShortcutPreferences.forEach { applyShortcutPreference($0) }
        applyArrowKeysPreference()
        applyVimKeysPreferenceWithoutDialogs()
    }

    static func preferenceChanged(_ key: String) {
        switch key {
        case "shortcutCount":
            applyActiveShortcutPreferences()
            (0..<Preferences.shortcutCount).forEach { initializeShortcutRecorderState($0) }
            refreshShortcutUi()
        case "nextWindowGesture":
            refreshGestureRow()
        case let k where isShortcutPreferenceKey(k):
            if Preferences.nameToIndex(k) < Preferences.shortcutCount {
                syncShortcutRecorderControlValue(k)
                applyShortcutPreference(k)
            } else {
                removeShortcutIfExists(k)
            }
            refreshShortcutRows()
        case let k where staticManagedShortcutPreferences.contains(k):
            applyShortcutPreference(k)
        case "arrowKeysEnabled":
            applyArrowKeysPreference()
        case "vimKeysEnabled" where vimKeysCheckbox == nil:
            applyVimKeysPreferenceWithoutDialogs()
        default:
            break
        }
    }

    static func initTab() -> NSView {
        shortcutEditorViews = (0..<Preferences.maxShortcutCount).map { shortcutTab($0) }
        gestureEditorView = gestureTab(Preferences.gestureIndex)
        let shortcutsView = makeShortcutsView()
        let additionalControlsButton = NSButton(title: NSLocalizedString("Additional controls…", comment: ""), target: self, action: #selector(showAdditionalControlsSettings))
        let shortcutsButton = NSButton(title: NSLocalizedString("Shortcuts when active…", comment: ""), target: self, action: #selector(showShortcutsSettings))
        let tools = StackView([additionalControlsButton, shortcutsButton], .horizontal)
        let view = TableGroupSetView(originalViews: [shortcutsView], toolsViews: [tools], bottomPadding: 0, othersAlignment: .leading, toolsAlignment: .trailing)
        shortcutsWhenActiveSheet = ShortcutsWhenActiveSheet()
        additionalControlsSheet = AdditionalControlsSheet()
        refreshShortcutUi()
        (0..<Preferences.shortcutCount).forEach { initializeShortcutRecorderState($0) }
        return view
    }

    private static func makeShortcutsView() -> NSView {
        let sidebar = makeShortcutSidebar()
        let editorPane = makeEditorPane()
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let content = NSStackView(views: [sidebar, separator, editorPane])
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.tableBackgroundColor.cgColor
        content.layer?.cornerRadius = TableGroupView.cornerRadius
        content.layer?.borderColor = NSColor.tableBorderColor.cgColor
        content.layer?.borderWidth = TableGroupView.borderWidth
        content.layer?.masksToBounds = true
        content.widthAnchor.constraint(equalToConstant: SettingsWindow.contentWidth).isActive = true
        sidebar.heightAnchor.constraint(equalTo: editorPane.heightAnchor).isActive = true
        return content
    }

    private static func makeEditorPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(equalToConstant: shortcutEditorWidth).isActive = true
        var views = shortcutEditorViews
        if let gestureEditorView {
            views.append(gestureEditorView)
        }
        let editorsStack = NSStackView(views: views)
        editorsStack.orientation = .vertical
        editorsStack.alignment = .leading
        editorsStack.spacing = 0
        editorsStack.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(editorsStack)
        NSLayoutConstraint.activate([
            editorsStack.topAnchor.constraint(equalTo: pane.topAnchor),
            editorsStack.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editorsStack.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            editorsStack.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        return pane
    }

    private static func makeShortcutSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: shortcutSidebarWidth).isActive = true
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.25).cgColor
        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        listContainer.wantsLayer = true
        listContainer.layer?.backgroundColor = NSColor.tableBackgroundColor.cgColor
        listContainer.layer?.cornerRadius = TableGroupView.cornerRadius
        listContainer.layer?.borderColor = NSColor.tableBorderColor.cgColor
        listContainer.layer?.borderWidth = TableGroupView.borderWidth
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        shortcutRowsStackView = rows
        let rowsScrollView = ControlsSidebarScrollView()
        rowsScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.drawsBackground = false
        rowsScrollView.hasVerticalScroller = true
        rowsScrollView.hasHorizontalScroller = false
        rowsScrollView.scrollerStyle = .overlay
        rowsScrollView.verticalScrollElasticity = .none
        rowsScrollView.usesPredominantAxisScrolling = true
        let documentView = FlippedView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.documentView = documentView
        documentView.addSubview(rows)
        let gestureSeparator = NSView()
        gestureSeparator.translatesAutoresizingMaskIntoConstraints = false
        gestureSeparator.wantsLayer = true
        gestureSeparator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        let gestureRow = ShortcutSidebarRow()
        gestureRow.onClick = { _, _ in selectGesture() }
        gestureRow.onMouseEntered = { _, _ in gestureRow.setHovered(true) }
        gestureRow.onMouseExited = { _, _ in gestureRow.setHovered(false) }
        gestureSidebarRow = gestureRow
        listContainer.addSubview(rowsScrollView)
        listContainer.addSubview(gestureSeparator)
        listContainer.addSubview(gestureRow)
        let countButtons = NSSegmentedControl(labels: ["+", "-"], trackingMode: .momentary, target: self, action: #selector(updateShortcutCount(_:)))
        countButtons.translatesAutoresizingMaskIntoConstraints = false
        countButtons.segmentStyle = .rounded
        countButtons.setWidth(28, forSegment: 0)
        countButtons.setWidth(28, forSegment: 1)
        shortcutCountButtons = countButtons
        let buttonsRow = NSStackView(views: [countButtons])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .leading
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(listContainer)
        sidebar.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            listContainer.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 10),
            listContainer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            listContainer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            listContainer.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -10),
            documentView.widthAnchor.constraint(equalTo: rowsScrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: rowsScrollView.contentView.heightAnchor),
            rows.topAnchor.constraint(equalTo: documentView.topAnchor),
            rows.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            rowsScrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            rowsScrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            rowsScrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            rowsScrollView.bottomAnchor.constraint(equalTo: gestureSeparator.topAnchor),
            gestureSeparator.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            gestureSeparator.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            gestureSeparator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth),
            gestureSeparator.bottomAnchor.constraint(equalTo: gestureRow.topAnchor),
            gestureRow.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            gestureRow.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            gestureRow.heightAnchor.constraint(equalToConstant: sidebarRowHeight),
            gestureRow.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            buttonsRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            buttonsRow.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -10),
        ])
        refreshGestureRow()
        return sidebar
    }

    private static func shortcutTab(_ index: Int) -> TableGroupView {
        let holdName = Preferences.indexToName("holdShortcut", index)
        let holdValue = UserDefaults.standard.string(forKey: holdName) ?? ""
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), holdName, holdValue, false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press", comment: "")))
        let nextName = Preferences.indexToName("nextWindowShortcut", index)
        let nextValue = UserDefaults.standard.string(forKey: nextName) ?? ""
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), nextName, nextValue, labelPosition: .right)
        return controlTab(index, holdShortcut + [nextWindowShortcut[0]], shortcutEditorWidth)
    }

    private static func gestureTab(_ index: Int) -> TableGroupView {
        let message = NSLocalizedString("You may need to disable some conflicting system gestures", comment: "")
        let button = NSButton(title: NSLocalizedString("Open Trackpad Settings…", comment: ""), target: self, action: #selector(openSystemGestures(_:)))
        let infoBtn = LabelAndControl.makeInfoButton(searchableTooltipTexts: [message], onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: message, extraView: button)
        })
        let gesture = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
        let gestureWithTooltip = NSStackView()
        gestureWithTooltip.orientation = .horizontal
        gestureWithTooltip.alignment = .centerY
        let dummyRecorderForHeight = CustomRecorderControl("d", true, "dummy")
        gestureWithTooltip.setViews([gesture, dummyRecorderForHeight], in: .trailing)
        gestureWithTooltip.setViews([infoBtn], in: .leading)
        gestureWithTooltip.heightAnchor.constraint(equalTo: dummyRecorderForHeight.heightAnchor).isActive = true
        dummyRecorderForHeight.isHidden = true
        return controlTab(index, [gestureWithTooltip], shortcutEditorWidth)
    }

    private static func controlTab(_ index: Int, _ trigger: [NSView], _ width: CGFloat) -> TableGroupView {
        let appsToShow = LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", index), AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", index), SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", index), ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", index), ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", index), ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", index), ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
        let showWindowlessApps = LabelAndControl.makeDropdown(Preferences.indexToName("showWindowlessApps", index), ShowHowPreference.allCases)
        let windowOrder = LabelAndControl.makeDropdown(Preferences.indexToName("windowOrder", index), WindowOrderPreference.allCases)
        let table = TableGroupView(width: width)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger", comment: ""), rightViews: trigger))
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from applications", comment: ""))], rightViews: [appsToShow])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from Spaces", comment: ""))], rightViews: [spacesToShow])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from screens", comment: ""))], rightViews: [screensToShow])
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""), rightViews: [showMinimizedWindows]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""), rightViews: [showHiddenWindows]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""), rightViews: [showFullscreenWindows]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show apps with no open window", comment: ""), rightViews: [showWindowlessApps]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Order windows by", comment: ""), rightViews: [windowOrder]))
        return table
    }

    private static func refreshShortcutUi() {
        if selectedShortcutIndex != gestureSelectionIndex {
            selectedShortcutIndex = max(0, min(selectedShortcutIndex, Preferences.shortcutCount - 1))
        }
        refreshShortcutRows()
        refreshGestureRow()
        refreshShortcutSelection()
        refreshShortcutCountButtons()
    }

    private static func refreshShortcutRows() {
        guard let rows = shortcutRowsStackView else { return }
        clearArrangedSubviews(rows)
        shortcutRows.removeAll(keepingCapacity: true)
        for index in 0..<Preferences.shortcutCount {
            let row = ShortcutSidebarRow()
            row.setContent(shortcutTitle(index), shortcutSummary(index))
            row.setSelected(index == selectedShortcutIndex && selectedShortcutIndex != gestureSelectionIndex)
            row.onClick = { _, _ in selectShortcut(index) }
            row.onMouseEntered = { _, _ in row.setHovered(true) }
            row.onMouseExited = { _, _ in row.setHovered(false) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: sidebarRowHeight).isActive = true
            shortcutRows.append(row)
            if index < Preferences.shortcutCount - 1 {
                let separator = NSView()
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.wantsLayer = true
                separator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
                rows.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
                separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
            }
        }
    }

    private static func refreshShortcutSelection() {
        shortcutRows.enumerated().forEach { $1.setSelected($0 == selectedShortcutIndex) }
        shortcutEditorViews.enumerated().forEach { index, view in
            view.isHidden = index != selectedShortcutIndex || index >= Preferences.shortcutCount
        }
        gestureSidebarRow?.setSelected(selectedShortcutIndex == gestureSelectionIndex)
        gestureEditorView?.isHidden = selectedShortcutIndex != gestureSelectionIndex
    }

    private static func refreshShortcutCountButtons() {
        shortcutCountButtons?.setEnabled(Preferences.shortcutCount < Preferences.maxShortcutCount, forSegment: 0)
        shortcutCountButtons?.setEnabled(Preferences.shortcutCount > Preferences.minShortcutCount && selectedShortcutIndex != gestureSelectionIndex, forSegment: 1)
    }

    private static func selectShortcut(_ index: Int) {
        guard (0..<Preferences.shortcutCount).contains(index) else { return }
        selectedShortcutIndex = index
        refreshShortcutSelection()
        refreshShortcutCountButtons()
    }

    private static func selectGesture() {
        selectedShortcutIndex = gestureSelectionIndex
        refreshShortcutSelection()
        refreshShortcutCountButtons()
    }

    @objc private static func updateShortcutCount(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        sender.selectedSegment = -1
        if segment == 0 {
            addShortcutSlot()
        } else if segment == 1 && selectedShortcutIndex != gestureSelectionIndex {
            removeShortcutSlot()
        }
    }

    private static func addShortcutSlot() {
        let currentCount = Preferences.shortcutCount
        guard currentCount < Preferences.maxShortcutCount else { return }
        resetShortcutPreferences(currentCount)
        setAddedShortcutTriggerDefaults(currentCount)
        selectedShortcutIndex = currentCount
        Preferences.set("shortcutCount", String(currentCount + 1))
        initializeShortcutRecorderState(currentCount)
    }

    private static func removeShortcutSlot() {
        let currentCount = Preferences.shortcutCount
        guard currentCount > Preferences.minShortcutCount, selectedShortcutIndex != gestureSelectionIndex else { return }
        let removedIndex = min(selectedShortcutIndex, currentCount - 1)
        if removedIndex < currentCount - 1 {
            for index in removedIndex..<(currentCount - 1) {
                copyShortcutPreferences(index + 1, index)
            }
        }
        resetShortcutPreferences(currentCount - 1)
        selectedShortcutIndex = min(removedIndex, currentCount - 2)
        Preferences.set("shortcutCount", String(currentCount - 1))
    }

    private static func resetShortcutPreferences(_ index: Int) {
        removableShortcutPreferences.forEach {
            Preferences.remove(Preferences.indexToName($0, index), false)
        }
    }

    private static func setAddedShortcutTriggerDefaults(_ index: Int) {
        Preferences.set(Preferences.indexToName("holdShortcut", index), "⌥", false)
        Preferences.set(Preferences.indexToName("nextWindowShortcut", index), "", false)
        Preferences.set(Preferences.indexToName("appsToShow", index), AppsToShowPreference.all.indexAsString, false)
    }

    private static func copyShortcutPreferences(_ fromIndex: Int, _ toIndex: Int) {
        removableShortcutPreferences.forEach { baseName in
            let fromKey = Preferences.indexToName(baseName, fromIndex)
            let toKey = Preferences.indexToName(baseName, toIndex)
            if let value = UserDefaults.standard.string(forKey: fromKey) {
                Preferences.set(toKey, value, false)
            } else {
                Preferences.remove(toKey, false)
            }
        }
    }

    private static func initializeShortcutRecorderState(_ index: Int) {
        guard index < Preferences.shortcutCount else { return }
        let holdControlId = Preferences.indexToName("holdShortcut", index)
        let nextControlId = Preferences.indexToName("nextWindowShortcut", index)
        syncShortcutRecorderControlValue(holdControlId)
        syncShortcutRecorderControlValue(nextControlId)
        shortcutDropdownPreferences.forEach { syncShortcutDropdownControlValue(Preferences.indexToName($0, index)) }
        if let holdShortcut = shortcutControls[holdControlId]?.0 {
            shortcutChangedCallback(holdShortcut)
        }
        if let nextWindowShortcut = shortcutControls[nextControlId]?.0 {
            shortcutChangedCallback(nextWindowShortcut)
        }
    }

    private static func syncShortcutRecorderControlValue(_ controlId: String) {
        guard let control = shortcutControls[controlId]?.0 else { return }
        let value = UserDefaults.standard.string(forKey: controlId) ?? ""
        control.objectValue = value.isEmpty ? nil : Shortcut(keyEquivalent: value)
    }

    private static func syncShortcutDropdownControlValue(_ controlId: String) {
        let index = Preferences.nameToIndex(controlId)
        guard index < shortcutEditorViews.count else { return }
        guard let dropdown = findDropdownControl(shortcutEditorViews[index], controlId) else { return }
        guard dropdown.numberOfItems > 0 else { return }
        let selectedIndex = UserDefaults.standard.string(forKey: controlId).flatMap(Int.init) ?? 0
        dropdown.selectItem(at: min(max(0, selectedIndex), dropdown.numberOfItems - 1))
    }

    private static func findDropdownControl(_ root: NSView, _ controlId: String) -> NSPopUpButton? {
        if let dropdown = root as? NSPopUpButton, dropdown.identifier?.rawValue == controlId {
            return dropdown
        }
        for child in root.subviews {
            if let found = findDropdownControl(child, controlId) {
                return found
            }
        }
        return nil
    }

    private static func shortcutTitle(_ index: Int) -> String {
        return NSLocalizedString("Shortcut", comment: "") + " " + String(index + 1)
    }

    private static func shortcutSummary(_ index: Int) -> String {
        let holdShortcut = UserDefaults.standard.string(forKey: Preferences.indexToName("holdShortcut", index)) ?? ""
        let nextWindowShortcut = UserDefaults.standard.string(forKey: Preferences.indexToName("nextWindowShortcut", index)) ?? ""
        if nextWindowShortcut.isEmpty {
            return holdShortcut.isEmpty ? NSLocalizedString("Not set", comment: "") : holdShortcut
        }
        return holdShortcut + " + " + nextWindowShortcut
    }

    private static func gestureTitle() -> String {
        return NSLocalizedString("Gesture", comment: "")
    }

    private static func gestureSummary() -> String {
        return Preferences.nextWindowGesture.localizedString
    }

    private static func refreshGestureRow() {
        guard let gestureSidebarRow else { return }
        gestureSidebarRow.setContent(gestureTitle(), gestureSummary())
        gestureSidebarRow.setSelected(selectedShortcutIndex == gestureSelectionIndex)
    }

    private static func clearArrangedSubviews(_ stackView: NSStackView) {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private static func isShortcutPreferenceKey(_ key: String) -> Bool {
        return (0..<Preferences.maxShortcutCount).contains(where: { index in
            ["holdShortcut", "nextWindowShortcut"].contains { key == Preferences.indexToName($0, index) }
        })
    }

    private static func applyActiveShortcutPreferences() {
        (0..<Preferences.maxShortcutCount).forEach { index in
            ["holdShortcut", "nextWindowShortcut"].forEach { base in
                let key = Preferences.indexToName(base, index)
                if index < Preferences.shortcutCount {
                    applyShortcutPreference(key)
                } else {
                    removeShortcutIfExists(key)
                }
            }
        }
    }

    @objc static func showShortcutsSettings() {
        App.app.settingsWindow.beginSheetWithSearchHighlight(shortcutsWhenActiveSheet)
    }

    @objc static func showAdditionalControlsSettings() {
        App.app.settingsWindow.beginSheetWithSearchHighlight(additionalControlsSheet)
    }

    private static func addShortcut(_ triggerPhase: ShortcutTriggerPhase, _ scope: ShortcutScope, _ shortcut: Shortcut, _ controlId: String, _ index: Int?) {
        let atShortcut = ATShortcut(shortcut, controlId, scope, triggerPhase, index)
        removeShortcutIfExists(controlId)
        shortcuts[controlId] = atShortcut
        if scope == .global {
            KeyboardEvents.addGlobalShortcut(controlId, atShortcut.shortcut)
            ControlsTab.toggleNativeCommandTabIfNeeded()
        }
    }

    static func toggleNativeCommandTabIfNeeded() {
        let nativeHotkeys: [CGSSymbolicHotKey: (Shortcut) -> Bool] = [
            .commandTab: { shortcut in shortcut.carbonModifierFlags == cmdKey && shortcut.carbonKeyCode == kVK_Tab },
            .commandShiftTab: { shortcut in CustomRecorderControlTestable.combinedModifiersMatch(shortcut.carbonModifierFlags, UInt32(cmdKey | shiftKey)) && shortcut.carbonKeyCode == kVK_Tab },
            .commandKeyAboveTab: { shortcut in shortcut.carbonModifierFlags == cmdKey && shortcut.carbonKeyCode == kVK_ANSI_Grave },
        ]
        var overlappingHotkeys = shortcuts.values.compactMap { atShortcut in nativeHotkeys.first { $1(atShortcut.shortcut) }?.key }
        if overlappingHotkeys.contains(.commandTab) && !overlappingHotkeys.contains(.commandShiftTab) {
            overlappingHotkeys.append(.commandShiftTab)
        }
        let nonOverlappingHotkeys: [CGSSymbolicHotKey] = Array(Set(nativeHotkeys.keys).symmetricDifference(Set(overlappingHotkeys)))
        setNativeCommandTabEnabled(false, overlappingHotkeys)
        setNativeCommandTabEnabled(true, nonOverlappingHotkeys)
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if isShortcutPreferenceKey(controlId) && Preferences.nameToIndex(controlId) >= Preferences.shortcutCount {
            return
        }
        if controlId.hasPrefix("holdShortcut") {
            let i = Preferences.nameToIndex(controlId)
            let holdShortcut = UserDefaults.standard.string(forKey: controlId) ?? ""
            guard let shortcut = Shortcut(keyEquivalent: holdShortcut) else {
                removeShortcutIfExists(controlId)
                return
            }
            addShortcut(.up, .global, shortcut, controlId, i)
            if let nextWindowShortcut = shortcutControls[Preferences.indexToName("nextWindowShortcut", i)]?.0 {
                nextWindowShortcut.restrictModifiers([(sender as! CustomRecorderControl).objectValue!.modifierFlags])
                shortcutChangedCallback(nextWindowShortcut)
            }
        } else {
            let newValue = combineHoldAndNextWindow(controlId, sender)
            let newShortcut = Shortcut(keyEquivalent: newValue)
            if newValue.isEmpty || newShortcut == nil {
                removeShortcutIfExists(controlId)
                restrictModifiersOfHoldShortcut(controlId, [])
                (sender as! CustomRecorderControl).objectValue = nil
            } else {
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, newShortcut!, controlId, nil)
                restrictModifiersOfHoldShortcut(controlId, [(sender as! CustomRecorderControl).objectValue!.modifierFlags])
            }
        }
    }

    private static func restrictModifiersOfHoldShortcut(_ controlId: String, _ modifiers: NSEvent.ModifierFlags) {
        if controlId.hasPrefix("nextWindowShortcut") {
            let i = Preferences.nameToIndex(controlId)
            if let holdShortcut = shortcutControls[Preferences.indexToName("holdShortcut", i)]?.0 {
                holdShortcut.restrictModifiers(modifiers)
            }
        }
    }

    static func combineHoldAndNextWindow(_ controlId: String, _ sender: NSControl) -> String {
        let baseValue = (sender as! RecorderControl).stringValue
        if baseValue == "" {
            return ""
        }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = UserDefaults.standard.string(forKey: Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId))) ?? ""
            return holdShortcut + baseValue
        }
        return baseValue
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        applyArrowKeysPreference()
    }

    @objc static func vimKeysEnabledCallback(_ sender: NSControl) {
        if (sender as! Switch).state == .on {
            if isClearVimKeysSuccessful() {
                vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
            } else {
                (sender as! Switch).state = .off
                Preferences.remove("vimKeysEnabled")
            }
        } else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
        }
    }

    private static func isClearVimKeysSuccessful() -> Bool {
        var conflicts = [String: String]()
        shortcuts.forEach {
            let keymap = $1.shortcut.characters
            if keymap != nil && vimKeyActions.keys.contains(keymap!) {
                let control_id = $1.id
                guard !vimKeyActions.values.contains(control_id) else { return }
                if let label = conflictLabel(control_id) {
                    conflicts[control_id] = label
                }
            }
        }
        if !conflicts.isEmpty {
            if App.app.settingsWindow == nil || !shouldClearConflictingShortcuts(conflicts.map { $0.value }) {
                return false
            }
            conflicts.forEach {
                removeShortcutIfExists($0.key)
                let existing = shortcutControls[$0.key]
                if existing != nil {
                    existing!.0.objectValue = nil
                    shortcutChangedCallback(existing!.0)
                    LabelAndControl.controlWasChanged(existing!.0, $0.key)
                }
            }
        }
        return true
    }

    private static func conflictLabel(_ controlId: String) -> String? {
        if let shortcutControl = shortcutControls[controlId] {
            return shortcutControl.1
        }
        if arrowKeys.contains(controlId) {
            return NSLocalizedString("Arrow keys", comment: "")
        }
        if vimKeyActions.values.contains(controlId) {
            return NSLocalizedString("Vim keys", comment: "")
        }
        return nil
    }

    private static func shouldClearConflictingShortcuts(_ conflicts: [String]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        let informativeText = conflicts.map { "• " + $0 }.joined(separator: "\n")
        alert.informativeText = String(format: NSLocalizedString("Vim keys already assigned to other actions:\n%@", comment: ""), informativeText.replacingOccurrences(of: " ", with: "\u{00A0}"))
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        let userChoice = alert.runModal()
        return userChoice == .alertFirstButtonReturn
    }

    private static func removeShortcutIfExists(_ controlId: String) {
        if let atShortcut = shortcuts[controlId] {
            if atShortcut.scope == .global {
                KeyboardEvents.removeGlobalShortcut(controlId, atShortcut.shortcut)
            }
            shortcuts.removeValue(forKey: controlId)
            if atShortcut.scope == .global {
                ControlsTab.toggleNativeCommandTabIfNeeded()
            }
        }
    }

    private static func applyShortcutPreference(_ controlId: String) {
        if isShortcutPreferenceKey(controlId) && Preferences.nameToIndex(controlId) >= Preferences.shortcutCount {
            removeShortcutIfExists(controlId)
            return
        }
        if controlId.hasPrefix("holdShortcut") {
            applyHoldShortcutPreference(controlId)
            applyShortcutPreference(Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(controlId)))
            return
        }
        let shortcutString = combinedShortcutString(controlId)
        guard !shortcutString.isEmpty, let shortcut = Shortcut(keyEquivalent: shortcutString) else {
            removeShortcutIfExists(controlId)
            restrictModifiersOfHoldShortcut(controlId, [])
            return
        }
        addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, shortcut, controlId, nil)
        restrictModifiersOfHoldShortcut(controlId, [shortcut.modifierFlags])
    }

    private static func applyHoldShortcutPreference(_ controlId: String) {
        let i = Preferences.nameToIndex(controlId)
        let holdShortcut = UserDefaults.standard.string(forKey: controlId) ?? ""
        guard let shortcut = Shortcut(keyEquivalent: holdShortcut) else {
            removeShortcutIfExists(controlId)
            return
        }
        addShortcut(.up, .global, shortcut, controlId, i)
    }

    private static func combinedShortcutString(_ controlId: String) -> String {
        guard let baseValue = UserDefaults.standard.string(forKey: controlId), !baseValue.isEmpty else {
            return ""
        }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = UserDefaults.standard.string(forKey: Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId))) ?? ""
            return holdShortcut + baseValue
        }
        return baseValue
    }

    private static func applyArrowKeysPreference() {
        if Preferences.arrowKeysEnabled {
            arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
        } else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
        }
    }

    private static func applyVimKeysPreferenceWithoutDialogs() {
        guard Preferences.vimKeysEnabled else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            return
        }
        if hasVimKeysConflictWithoutUi() {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            Preferences.set("vimKeysEnabled", "false", false)
            return
        }
        vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
    }

    private static func hasVimKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            if let key = $0.shortcut.characters, vimKeyActions.keys.contains(key) {
                return !vimKeyActions.values.contains($0.id)
            }
            return false
        }
    }

    @objc private static func openSystemGestures(_ sender: NSButton) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    static func executeAction(_ action: String) {
        if let staticAction = shortcutsActions[action] {
            staticAction()
            return
        }
        if action.hasPrefix("holdShortcut") {
            App.app.focusTarget()
            return
        }
        if action.hasPrefix("nextWindowShortcut") {
            App.app.showUiOrCycleSelection(Preferences.nameToIndex(action), false)
        }
    }
}
