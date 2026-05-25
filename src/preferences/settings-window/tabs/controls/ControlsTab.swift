import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class ControlsTab {
    static var shortcuts = [String: ATShortcut]()
    static var shortcutControls = [String: (CustomRecorderControl, String)]()
    static var arrowKeysCheckbox: Switch!
    static var vimKeysCheckbox: Switch!

    static var shortcutsWhenActiveSheet: ShortcutsWhenActiveSheet!
    static var additionalControlsSheet: AdditionalControlsSheet!

    private static let shortcutSidebarWidth = CGFloat(175)
    private static let sidebarRowHeight = CGFloat(52)
    private static let sidebarHorizontalPadding = TableGroupView.padding
    private static let shortcutEditorTopBottomPadding = TableGroupView.padding
    private static let shortcutEditorRightPadding = TableGroupView.padding
    private static var shortcutEditorWidth: CGFloat { SettingsWindow.contentWidth - shortcutSidebarWidth - 1 }
    private static var shortcutEditorContentWidth: CGFloat { shortcutEditorWidth - shortcutEditorRightPadding }
    /// Minimum height for a shortcut editor's content block. Anchored to roughly the height of the
    /// Filtering pane (the tallest of the three tabs) so switching to a short tab like Ordering
    /// doesn't make the surrounding rounded section visibly snap up — the bottom just gets
    /// whitespace instead.
    private static let controlTabMinHeight = CGFloat(400)
    /// Fixed height for the Trigger row's content (recorder + labels). We pin this rather than
    /// derive it from a dummy recorder's intrinsic size, because `RecorderControl`'s intrinsic
    /// height isn't guaranteed to be set at the moment `TableGroupView.setMainRow` snapshots
    /// `mainRow.fittingSize.height` — depending on when in the layout cycle the row is built,
    /// the snapshot can land before the style's constraints have populated, yielding inconsistent
    /// row heights across shortcuts.
    private static let triggerRowContentHeight = CGFloat(22)
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
        "showAppsOrWindows", "showTabsAsWindows",
        "appearanceStyleOverride", "appearanceSizeOverride", "appearanceThemeOverride",
        "shortcutStyleOverride", "previewFocusedWindowOverride",
    ]
    private static let shortcutDropdownPreferences = [
        "appsToShow", "spacesToShow", "screensToShow",
        "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows", "showWindowlessApps",
        "windowOrder",
        "showAppsOrWindows",
    ]
    private static let arrowKeys = ["←", "→", "↑", "↓"]
    private static let arrowKeyCodes: Set<KeyCode> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
    private static let vimKeyActions = [
        "h": "vimCycleLeft",
        "l": "vimCycleRight",
        "k": "vimCycleUp",
        "j": "vimCycleDown",
    ]

    private static var selectedShortcutIndex = 0
    private static var selectedTabSegment = 0
    private static var shortcutRowsStackView: NSStackView?
    private static var shortcutRows = [SidebarListRow]()
    private static var shortcutEditorViews = [NSView]()
    private static var gestureSidebarRow: SidebarListRow?
    private static var gestureEditorView: NSView?
    private static var shortcutCountButtons: NSSegmentedControl?
    private static var shortcutRowsScrollView: NSScrollView?
    private static var shortcutRowsScrollObserver: NSObjectProtocol?
    /// Per-shortcut tab control + its content panes (one per segment, in segment order). Keyed by
    /// shortcut index (0..maxShortcutCount, with `gestureIndex` for the gesture). Updated in
    /// `controlTab(_:_:_:)`, read by `switchControlTabSection` and `selectShortcutAndShowAppearance`.
    /// Panes order matches the segments: Filtering, Appearance, Ordering and Grouping.
    private static var tabContentsByIndex = [Int: (panes: [NSView], tabControl: NSSegmentedControl)]()
    /// Maps each Filtering/Appearance `tabControl` to the two content views (one per segment).
    /// Consulted by `SettingsWindow.highlightTarget(_ segmentedControl:)` so a search match deep
    /// inside the Filtering or Appearance subtree turns the corresponding tab segment yellow —
    /// same affordance as sheet buttons, which highlight when their sheet's contents match.
    static var tabSegmentSubtrees = [ObjectIdentifier: [NSView]]()
    /// Override control views keyed by the indexed UserDefaults key (e.g. `appearanceStyleOverride2`).
    /// Used by `syncOverrideControlToGlobal` to re-display the global value on non-overridden controls
    /// after the user changes the global setting.
    private static var overrideControls = [String: NSView]()
    /// Unlink buttons keyed by the indexed UserDefaults key. Visible iff `hasOverride` is true.
    private static var unlinkButtons = [String: NSButton]()
    /// Pro-badge views for the Pro-gated override segments. Keyed by the indexed UserDefaults key.
    /// Stored so `extraAction` callbacks and the Pro-lock observer can call
    /// `AppearanceTab.refreshTrailingSegmentBadge(...)` per shortcut.
    private static var overrideProBadges = [String: ProBadgeView.SegmentOverlay]()

    static func initializePreferencesDependentState() {
        applyActiveShortcutPreferences()
        staticManagedShortcutPreferences.forEach { applyShortcutPreference($0) }
        applyArrowKeysPreferenceWithoutDialogs()
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
        case let k where Preferences.overrideToGlobalKey.values.contains(k):
            // A global appearance setting changed; resnap non-overridden controls and refresh
            // the AppearanceTab "Overridden in Shortcut:" labels.
            syncOverrideControlsToGlobal()
            AppearanceTab.refreshAllOverrideInfoLabels()
        case let k where isOverrideKey(k):
            // An override key changed (e.g. user picked a different value, or remembered-restore wrote).
            refreshUnlinkButtons()
            AppearanceTab.refreshAllOverrideInfoLabels()
        case "arrowKeysEnabled" where arrowKeysCheckbox == nil:
            applyArrowKeysPreferenceWithoutDialogs()
        case "vimKeysEnabled" where vimKeysCheckbox == nil:
            applyVimKeysPreferenceWithoutDialogs()
        default:
            break
        }
    }

    static func inputSourceChanged() {
        refreshShortcutRows()
        refreshShortcutControlsDisplay()
    }

    private static var proLockObserver: NSObjectProtocol?

    static func initTab() -> NSView {
        shortcutEditorViews = (0..<Preferences.maxShortcutCount).map { shortcutTab($0) }
        gestureEditorView = gestureTab(Preferences.gestureIndex)
        let shortcutsView = makeShortcutsView()
        let additionalControlsButton = NSButton(title: NSLocalizedString("Additional controls…", comment: ""), target: self, action: #selector(showAdditionalControlsSettings))
        let shortcutsButton = NSButton(title: NSLocalizedString("Shortcuts when active…", comment: ""), target: self, action: #selector(showShortcutsSettings))
        let tools = StackView([additionalControlsButton, shortcutsButton], .horizontal)
        // `padding: 0` — section's left margin is already applied by `SettingsWindow.addSection`.
        // See the same comment in `AppearanceTab.makeView` for the alignment rationale.
        let view = TableGroupSetView(originalViews: [shortcutsView], toolsViews: [tools], padding: 0, bottomPadding: 0, othersAlignment: .leading, toolsAlignment: .trailing)
        shortcutsWhenActiveSheet = ShortcutsWhenActiveSheet()
        additionalControlsSheet = AdditionalControlsSheet()
        refreshShortcutUi()
        (0..<Preferences.shortcutCount).forEach { initializeShortcutRecorderState($0) }
        if proLockObserver == nil {
            proLockObserver = NotificationCenter.default.addObserver(
                forName: ProTransitionManager.proLockStateDidChangeNotification,
                object: nil, queue: .main
            ) { _ in
                refreshShortcutUi()
                // The 3 Pro-gated index-0 overrides may have been snapshot+downgraded by
                // `ProTransitionState.onProLockEngaged`; the bound segmented/radio controls hold
                // the now-stale pre-downgrade value. Resync them to the current stored value so
                // the UI reflects the locked state without requiring a Settings reopen.
                refreshGatedOverrideControlsFromStored()
            }
        }
        return view
    }

    static func cleanup() {
        if let observer = proLockObserver {
            NotificationCenter.default.removeObserver(observer)
            proLockObserver = nil
        }
        if let observer = shortcutRowsScrollObserver {
            NotificationCenter.default.removeObserver(observer)
            shortcutRowsScrollObserver = nil
        }
        // No .close() on sheets — see AppearanceTab.cleanup() comment.
        shortcutsWhenActiveSheet = nil
        additionalControlsSheet = nil
        arrowKeysCheckbox = nil
        vimKeysCheckbox = nil
        // shortcutControls holds CustomRecorderControl views; clear so ARC reclaims them.
        // (`shortcuts` is the runtime model dict and is populated independently of SettingsWindow at launch.)
        shortcutControls.removeAll()
        shortcutRows.removeAll()
        shortcutEditorViews.removeAll()
        tabContentsByIndex.removeAll()
        overrideControls.removeAll()
        unlinkButtons.removeAll()
        overrideProBadges.removeAll()
        tabSegmentSubtrees.removeAll()
        shortcutRowsStackView = nil
        gestureSidebarRow = nil
        gestureEditorView = nil
        shortcutCountButtons = nil
        shortcutRowsScrollView = nil
    }

    private static func makeShortcutsView() -> NSView {
        return makeSidebarEditorContainer(sidebar: makeShortcutSidebar(), editor: makeEditorPane())
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
            editorsStack.topAnchor.constraint(equalTo: pane.topAnchor, constant: shortcutEditorTopBottomPadding),
            editorsStack.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editorsStack.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -shortcutEditorRightPadding),
            editorsStack.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -shortcutEditorTopBottomPadding),
        ])
        return pane
    }

    private static func makeShortcutSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: shortcutSidebarWidth).isActive = true
        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false
        let shortcutsSection = SidebarListContainer()
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        shortcutRowsStackView = rows
        let rowsScrollView = ForwardingVerticalScrollView()
        rowsScrollView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.drawsBackground = false
        rowsScrollView.hasVerticalScroller = true
        rowsScrollView.verticalScrollElasticity = .none
        rowsScrollView.hasHorizontalScroller = false
        rowsScrollView.scrollerStyle = .overlay
        rowsScrollView.usesPredominantAxisScrolling = true
        rowsScrollView.contentView.postsBoundsChangedNotifications = true
        let documentView = ForwardingVerticalDocumentView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        rowsScrollView.documentView = documentView
        documentView.addSubview(rows)
        shortcutRowsScrollView = rowsScrollView
        installShortcutSidebarHoverObserver(rowsScrollView)
        let gestureSeparator = sidebarSeparatorView()
        let gestureRow = SidebarListRow()
        gestureRow.onClick = { _, _ in selectGesture() }
        gestureRow.onMouseEntered = { _, view in setHoveredShortcutRow(view as? SidebarListRow) }
        gestureRow.onMouseExited = { _, _ in setHoveredShortcutRow(nil) }
        gestureSidebarRow = gestureRow
        listContainer.addSubview(shortcutsSection)
        shortcutsSection.addSubview(rowsScrollView)
        shortcutsSection.addSubview(gestureSeparator)
        shortcutsSection.addSubview(gestureRow)
        // Use SF Symbols glyphs instead of literal "+"/"-" strings — NSSegmentedControl draws
        // those ASCII glyphs noticeably below the vertical center. Symbols center properly.
        let plus = NSImage.fromSymbol(.plus, pointSize: 11)
        let minus = NSImage.fromSymbol(.minus, pointSize: 11)
        let countButtons = NSSegmentedControl(images: [plus, minus], trackingMode: .momentary, target: self, action: #selector(updateShortcutCount(_:)))
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
        listContainer.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            listContainer.topAnchor.constraint(equalTo: sidebar.topAnchor),
            listContainer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            listContainer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: rowsScrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: rowsScrollView.contentView.heightAnchor),
            rows.topAnchor.constraint(equalTo: documentView.topAnchor),
            rows.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            shortcutsSection.topAnchor.constraint(equalTo: listContainer.topAnchor, constant: TableGroupView.padding),
            shortcutsSection.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: sidebarHorizontalPadding),
            shortcutsSection.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -sidebarHorizontalPadding),
            shortcutsSection.bottomAnchor.constraint(equalTo: buttonsRow.topAnchor, constant: -TableGroupView.padding),
            rowsScrollView.topAnchor.constraint(equalTo: shortcutsSection.topAnchor),
            rowsScrollView.leadingAnchor.constraint(equalTo: shortcutsSection.leadingAnchor),
            rowsScrollView.trailingAnchor.constraint(equalTo: shortcutsSection.trailingAnchor),
            rowsScrollView.bottomAnchor.constraint(equalTo: gestureSeparator.topAnchor),
            gestureSeparator.leadingAnchor.constraint(equalTo: shortcutsSection.leadingAnchor),
            gestureSeparator.trailingAnchor.constraint(equalTo: shortcutsSection.trailingAnchor),
            gestureSeparator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth),
            gestureSeparator.bottomAnchor.constraint(equalTo: gestureRow.topAnchor),
            gestureRow.leadingAnchor.constraint(equalTo: shortcutsSection.leadingAnchor),
            gestureRow.trailingAnchor.constraint(equalTo: shortcutsSection.trailingAnchor),
            gestureRow.heightAnchor.constraint(equalToConstant: sidebarRowHeight),
            gestureRow.bottomAnchor.constraint(equalTo: shortcutsSection.bottomAnchor),
            buttonsRow.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: sidebarHorizontalPadding),
            buttonsRow.trailingAnchor.constraint(lessThanOrEqualTo: listContainer.trailingAnchor, constant: -sidebarHorizontalPadding),
            buttonsRow.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: -TableGroupView.padding),
        ])
        refreshGestureRow()
        return sidebar
    }

    private static func shortcutTab(_ index: Int) -> NSView {
        let holdName = Preferences.indexToName("holdShortcut", index)
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), holdName, Preferences.shortcut(holdName), false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press", comment: "")))
        let nextName = Preferences.indexToName("nextWindowShortcut", index)
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), nextName, Preferences.shortcut(nextName), labelPosition: .right)
        // Pin the trigger row's content to a fixed height so every shortcut's Trigger row is
        // identical, regardless of `RecorderControl`'s intrinsic-size readiness at layout time.
        let triggerContent = NSStackView(views: holdShortcut + [nextWindowShortcut[0]])
        triggerContent.orientation = .horizontal
        triggerContent.alignment = .centerY
        triggerContent.spacing = TableGroupView.spacing
        triggerContent.heightAnchor.constraint(equalToConstant: triggerRowContentHeight).isActive = true
        return controlTab(index, [triggerContent], shortcutEditorContentWidth)
    }

    private static func gestureTab(_ index: Int) -> NSView {
        let message = NSLocalizedString("You may need to disable some conflicting system gestures", comment: "")
        let button = NSButton(title: NSLocalizedString("Open Trackpad Settings…", comment: ""), target: self, action: #selector(openSystemGestures(_:)))
        let infoBtn = LabelAndControl.makeInfoButton(searchableTooltipTexts: [message], onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: message, extraView: button)
        })
        let gesture = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
        let gestureWithTooltip = NSStackView()
        gestureWithTooltip.orientation = .horizontal
        gestureWithTooltip.alignment = .centerY
        gestureWithTooltip.setViews([gesture], in: .trailing)
        gestureWithTooltip.setViews([infoBtn], in: .leading)
        // Pin to the same fixed height the shortcut tab uses, so the Trigger row is consistent
        // across all entries in the sidebar (shortcuts AND the Gesture row).
        gestureWithTooltip.heightAnchor.constraint(equalToConstant: triggerRowContentHeight).isActive = true
        return controlTab(index, [gestureWithTooltip], shortcutEditorContentWidth)
    }

    private static func controlTab(_ index: Int, _ trigger: [NSView], _ width: CGFloat) -> NSView {
        let triggerTable = TableGroupView(width: width)
        triggerTable.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger", comment: ""), rightViews: trigger))
        let panes: [NSView] = [
            makeFilteringTable(index, width),
            makeAppearanceTable(index, width),
            makeOrderingGroupingTable(index, width),
        ]
        let labels = [
            NSLocalizedString("Filtering", comment: ""),
            NSLocalizedString("Appearance", comment: ""),
            NSLocalizedString("Ordering & Grouping", comment: ""),
        ]
        let tabControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: #selector(switchControlTabSection(_:)))
        tabControl.tag = index
        tabControl.selectedSegment = selectedTabSegment
        LabelAndControl.applySystemSelectedSegmentStyle(tabControl)
        tabControl.widthAnchor.constraint(equalToConstant: width).isActive = true
        // Pin each segment to an equal share of the control width. Without this the auto-sizing
        // gives each segment its intrinsic-content width, which `segmentedControlSegmentRects`
        // can't see — its even-split fallback would then misalign the yellow search highlight
        // from the actual segment boundary.
        let segmentWidth = width / CGFloat(labels.count)
        for i in 0..<labels.count {
            tabControl.setWidth(segmentWidth, forSegment: i)
        }
        for (i, pane) in panes.enumerated() {
            pane.isHidden = selectedTabSegment != i
        }
        tabContentsByIndex[index] = (panes: panes, tabControl: tabControl)
        tabSegmentSubtrees[ObjectIdentifier(tabControl)] = panes
        let container = NSStackView(views: [triggerTable, tabControl] + panes)
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = TableGroupSetView.tableGroupSpacing
        // Extra breathing room below the Trigger row — it's the headline action of the editor
        // and the tab control / content tables that follow are secondary configuration.
        container.setCustomSpacing(10, after: triggerTable)
        // Pin a minimum height so switching to a short tab (e.g. Ordering, 3 rows) doesn't snap
        // the surrounding shortcut section's rounded background up. The tallest tab (Filtering)
        // hits about this height; everything else gets bottom whitespace.
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: controlTabMinHeight).isActive = true
        return container
    }

    private static func makeFilteringTable(_ index: Int, _ width: CGFloat) -> NSView {
        let appsToShow = LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", index), AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", index), SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", index), ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", index), ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", index), ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", index), ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
        let showWindowlessApps = LabelAndControl.makeDropdown(Preferences.indexToName("showWindowlessApps", index), ShowHowPreference.allCases)
        let filteringTable = TableGroupView(width: width)
        filteringTable.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from applications", comment: ""))], rightViews: [appsToShow])
        filteringTable.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from Spaces", comment: ""))], rightViews: [spacesToShow])
        filteringTable.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from screens", comment: ""))], rightViews: [screensToShow])
        filteringTable.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""), rightViews: [showMinimizedWindows]))
        filteringTable.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""), rightViews: [showHiddenWindows]))
        filteringTable.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""), rightViews: [showFullscreenWindows]))
        filteringTable.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show apps with no open window", comment: ""), rightViews: [showWindowlessApps]))
        return filteringTable
    }

    /// "Ordering and Grouping" tab content: per-shortcut window-order and grouping preferences.
    private static func makeOrderingGroupingTable(_ index: Int, _ width: CGFloat) -> TableGroupView {
        let table = TableGroupView(width: width)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Group apps", comment: ""),
            rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("showAppsOrWindows", index), ShowAppsOrWindowsPreference.allCases)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Group tabs", comment: ""),
            rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("showTabsAsWindows", index), GroupTabsPreference.allCases)]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Order windows by", comment: ""),
            rightViews: [LabelAndControl.makeDropdown(Preferences.indexToName("windowOrder", index), WindowOrderPreference.allCases)]))
        return table
    }

    private static func makeAppearanceTable(_ index: Int, _ width: CGFloat) -> NSView {
        let table = TableGroupView(width: width)
        let sizeProIndex = AppearanceSizePreference.allCases.firstIndex(of: .auto)!
        let shortcutStyleProIndex = ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!
        let extraAction: () -> Void = {
            refreshUnlinkButtons()
            AppearanceTab.refreshAllOverrideInfoLabels()
        }
        // Style (radio buttons; non-thumbnails entries are Pro-gated)
        let styleKey = Preferences.indexToName("appearanceStyleOverride", index)
        let styleRadios = LabelAndControl.makeImageRadioButtons(
            styleKey, AppearanceStylePreference.allCases,
            extraAction: nil, buttonSpacing: 10,
            proGatedIndices: AppearanceTab.proGatedAppearanceStyleIndices())
        AppearanceTab.addProBadgesToStyleButtons(styleRadios)
        overrideControls[styleKey] = styleRadios
        if !Preferences.hasOverride("appearanceStyleOverride", index) {
            syncRadioButtons(styleRadios, to: Preferences.appearanceStyle.index)
        }
        installOverrideRadioButtonActions(styleRadios,
            baseName: "appearanceStyleOverride",
            index: index,
            valueAtIndex: { AppearanceStylePreference.allCases[$0].indexAsString },
            globalIndex: { Preferences.appearanceStyle.index },
            proGatedIndices: AppearanceTab.proGatedAppearanceStyleIndices(),
            onChange: extraAction)
        let styleUnlink = makeUnlinkButton("appearanceStyleOverride", index)
        let styleRow = NSStackView(views: [styleRadios, styleUnlink])
        styleRow.orientation = .horizontal
        styleRow.alignment = .centerY
        styleRow.spacing = TableGroupView.padding
        table.addRow(secondaryViews: [styleRow], secondaryViewsAlignment: .centerX)
        // Size (segmented control; `.auto` is Pro-gated)
        let sizeKey = Preferences.indexToName("appearanceSizeOverride", index)
        let sizeControl = LabelAndControl.makeSegmentedControl(sizeKey, AppearanceSizePreference.allCases, segmentWidth: 100, extraAction: nil)
        let sizeOverlay = AppearanceTab.addProBadgeToAutoSegment(sizeControl)
        overrideProBadges[sizeKey] = sizeOverlay
        overrideControls[sizeKey] = sizeControl
        if !Preferences.hasOverride("appearanceSizeOverride", index) {
            sizeControl.selectedSegment = Preferences.appearanceSize.index
            AppearanceTab.refreshTrailingSegmentBadge(sizeControl, proIndex: sizeProIndex, overlay: sizeOverlay)
        }
        installOverrideSegmentedAction(sizeControl,
            baseName: "appearanceSizeOverride",
            index: index,
            valueAtIndex: { AppearanceSizePreference.allCases[$0].indexAsString },
            globalIndex: { Preferences.appearanceSize.index },
            onChange: { [weak sizeControl] in
                extraAction()
                if let sc = sizeControl, let overlay = overrideProBadges[sizeKey] {
                    AppearanceTab.refreshTrailingSegmentBadge(sc, proIndex: sizeProIndex, overlay: overlay)
                }
            })
        wrapAppearanceSegmentProLockIntercept(sizeControl, key: sizeKey,
            proIndex: sizeProIndex,
            currentStoredIndex: { CachedUserDefaults.intFromMacroPref(sizeKey, AppearanceSizePreference.allCases) })
        sizeOverlay.badge.onWindowKeyChanged = { [weak sizeControl] in
            guard let sizeControl else { return }
            AppearanceTab.refreshTrailingSegmentBadge(sizeControl, proIndex: sizeProIndex, overlay: sizeOverlay)
        }
        let sizeUnlink = makeUnlinkButton("appearanceSizeOverride", index)
        table.addRow(leftText: NSLocalizedString("Size", comment: ""), rightViews: [sizeControl, sizeUnlink])
        // Theme (segmented control; not Pro-gated)
        let themeKey = Preferences.indexToName("appearanceThemeOverride", index)
        let themeControl = LabelAndControl.makeSegmentedControl(themeKey, AppearanceThemePreference.allCases, segmentWidth: 100, extraAction: nil)
        overrideControls[themeKey] = themeControl
        if !Preferences.hasOverride("appearanceThemeOverride", index) {
            themeControl.selectedSegment = Preferences.appearanceTheme.index
        }
        installOverrideSegmentedAction(themeControl,
            baseName: "appearanceThemeOverride",
            index: index,
            valueAtIndex: { AppearanceThemePreference.allCases[$0].indexAsString },
            globalIndex: { Preferences.appearanceTheme.index },
            onChange: extraAction)
        let themeUnlink = makeUnlinkButton("appearanceThemeOverride", index)
        table.addRow(leftText: NSLocalizedString("Theme", comment: ""), rightViews: [themeControl, themeUnlink])
        // After keys are released (segmented control; `.searchOnRelease` is Pro-gated)
        let shortcutStyleKey = Preferences.indexToName("shortcutStyleOverride", index)
        let shortcutStyleControl = LabelAndControl.makeSegmentedControl(shortcutStyleKey, ShortcutStylePreference.allCases, segmentWidth: 100, extraAction: nil)
        let shortcutStyleOverlay = AppearanceTab.addProBadgeToShortcutStyleSegment(shortcutStyleControl, proIndex: shortcutStyleProIndex)
        overrideProBadges[shortcutStyleKey] = shortcutStyleOverlay
        overrideControls[shortcutStyleKey] = shortcutStyleControl
        if !Preferences.hasOverride("shortcutStyleOverride", index) {
            shortcutStyleControl.selectedSegment = Preferences.shortcutStyle.index
            AppearanceTab.refreshTrailingSegmentBadge(shortcutStyleControl, proIndex: shortcutStyleProIndex, overlay: shortcutStyleOverlay)
        }
        installOverrideSegmentedAction(shortcutStyleControl,
            baseName: "shortcutStyleOverride",
            index: index,
            valueAtIndex: { ShortcutStylePreference.allCases[$0].indexAsString },
            globalIndex: { Preferences.shortcutStyle.index },
            onChange: { [weak shortcutStyleControl] in
                extraAction()
                if let sc = shortcutStyleControl, let overlay = overrideProBadges[shortcutStyleKey] {
                    AppearanceTab.refreshTrailingSegmentBadge(sc, proIndex: shortcutStyleProIndex, overlay: overlay)
                }
            })
        wrapAppearanceSegmentProLockIntercept(shortcutStyleControl, key: shortcutStyleKey,
            proIndex: shortcutStyleProIndex,
            currentStoredIndex: { CachedUserDefaults.intFromMacroPref(shortcutStyleKey, ShortcutStylePreference.allCases) })
        shortcutStyleOverlay.badge.onWindowKeyChanged = { [weak shortcutStyleControl] in
            guard let shortcutStyleControl else { return }
            AppearanceTab.refreshTrailingSegmentBadge(shortcutStyleControl, proIndex: shortcutStyleProIndex, overlay: shortcutStyleOverlay)
        }
        let shortcutStyleUnlink = makeUnlinkButton("shortcutStyleOverride", index)
        table.addRow(leftText: NSLocalizedString("After keys are released", comment: ""), rightViews: [shortcutStyleControl, shortcutStyleUnlink])
        // Preview selected window
        let previewKey = Preferences.indexToName("previewFocusedWindowOverride", index)
        let previewControl = LabelAndControl.makeSwitch(previewKey, extraAction: nil)
        overrideControls[previewKey] = previewControl
        if !Preferences.hasOverride("previewFocusedWindowOverride", index) {
            previewControl.setSilently(Preferences.previewSelectedWindow ? .on : .off)
        }
        installOverrideSwitchAction(previewControl, baseName: "previewFocusedWindowOverride", index: index, onChange: extraAction)
        let previewUnlink = makeUnlinkButton("previewFocusedWindowOverride", index)
        table.addRow(leftText: NSLocalizedString("Preview selected window", comment: ""), rightViews: [previewControl, previewUnlink])
        return table
    }

    /// Wrap a segmented control's `onAction` so clicking the Pro-gated segment while locked
    /// redirects to the Upgrade tab instead of writing the preference. Mirrors
    /// `AppearanceTab.wrapAppearanceSizeProLockIntercept` / `wrapShortcutStyleProLockIntercept`.
    private static func wrapAppearanceSegmentProLockIntercept(_ segmentedControl: NSSegmentedControl, key: String, proIndex: Int, currentStoredIndex: @escaping () -> Int) {
        let original = segmentedControl.onAction
        segmentedControl.onAction = { control in
            let segmented = control as! NSSegmentedControl
            if segmented.selectedSegment == proIndex && LicenseManager.shared.isProLocked {
                segmented.selectedSegment = currentStoredIndex()
                // `original` (which wraps `extraAction`) is what refreshes the overlay — we bail
                // before it fires, so resync the overlay manually now that we've reset the
                // selection. Otherwise the badge keeps its pre-click "selected" state and the
                // label/icon keep the selected text color.
                if let overlay = overrideProBadges[key] {
                    AppearanceTab.refreshTrailingSegmentBadge(segmented, proIndex: proIndex, overlay: overlay)
                }
                UpgradeTab.navigateToUpgradeTab()
                return
            }
            original?(control)
        }
    }

    @objc private static func switchControlTabSection(_ sender: NSSegmentedControl) {
        selectedTabSegment = sender.selectedSegment
        // Apply the same selection to every shortcut's editor so switching between shortcuts in the
        // sidebar keeps the user's chosen tab. Without this, only the clicked editor would update.
        for (_, contents) in tabContentsByIndex {
            contents.tabControl.selectedSegment = selectedTabSegment
            for (i, pane) in contents.panes.enumerated() {
                pane.isHidden = selectedTabSegment != i
            }
        }
    }

    private static func makeUnlinkButton(_ baseName: String, _ index: Int) -> NSButton {
        let key = Preferences.indexToName(baseName, index)
        let image = NSImage.fromSymbol(.link, pointSize: 14)
        let button = NSButton(image: image, target: self, action: #selector(unlinkOverride(_:)))
        button.identifier = NSUserInterfaceItemIdentifier("\(baseName)|\(index)")
        button.bezelStyle = .regularSquare
        button.isBordered = false
        if #available(macOS 10.14, *) {
            button.contentTintColor = .controlAccentColor
        }
        button.toolTip = NSLocalizedString("Sync with global value", comment: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.isHidden = !Preferences.hasOverride(baseName, index)
        unlinkButtons[key] = button
        return button
    }

    @objc private static func unlinkOverride(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else { return }
        let parts = identifier.split(separator: "|")
        guard parts.count == 2, let index = Int(parts[1]) else { return }
        let baseName = String(parts[0])
        Preferences.removeOverride(baseName, index)
        syncOverrideControlToGlobal(baseName, index)
        refreshUnlinkButtons()
        AppearanceTab.refreshAllOverrideInfoLabels()
    }

    /// Apply an `OverrideClickResolver.OverrideClickDecision` for a segmented/radio click.
    /// Reads override state from `Preferences.hasOverride` + UserDefaults (before any write).
    private static func applyOverrideClick(
        baseName: String,
        index: Int,
        newIndex: Int,
        valueAtIndex: (Int) -> String,
        globalIndex: () -> Int
    ) -> OverrideClickDecision {
        let key = Preferences.indexToName(baseName, index)
        let decision = OverrideClickResolver.decide(
            newIndex: newIndex,
            hasOverride: Preferences.hasOverride(baseName, index),
            storedOverrideValue: UserDefaults.standard.string(forKey: key),
            globalIndex: globalIndex(),
            valueAtIndex: valueAtIndex)
        if case .write(let value) = decision {
            Preferences.set(key, value)
        }
        return decision
    }

    private static func installOverrideSegmentedAction(
        _ control: NSSegmentedControl,
        baseName: String,
        index: Int,
        valueAtIndex: @escaping (Int) -> String,
        globalIndex: @escaping () -> Int,
        onChange: @escaping () -> Void
    ) {
        control.onAction = { c in
            let seg = c as! NSSegmentedControl
            let decision = applyOverrideClick(
                baseName: baseName, index: index,
                newIndex: seg.selectedSegment,
                valueAtIndex: valueAtIndex,
                globalIndex: globalIndex)
            if case .write = decision { onChange() }
        }
    }

    private static func installOverrideRadioButtonActions(
        _ stack: NSStackView,
        baseName: String,
        index: Int,
        valueAtIndex: @escaping (Int) -> String,
        globalIndex: @escaping () -> Int,
        proGatedIndices: Set<Int>,
        onChange: @escaping () -> Void
    ) {
        let key = Preferences.indexToName(baseName, index)
        let buttonViews = stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
        for (i, buttonView) in buttonViews.enumerated() {
            buttonView.onClick = { [weak stack] _ in
                guard let stack else { return }
                let buttons = stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
                if LicenseManager.shared.isProLocked && proGatedIndices.contains(i) {
                    let storedIndex = Int(UserDefaults.standard.string(forKey: key) ?? "") ?? -1
                    for (j, b) in buttons.enumerated() { b.state = (j == storedIndex) ? .on : .off }
                    UpgradeTab.navigateToUpgradeTab()
                    return
                }
                let decision = applyOverrideClick(
                    baseName: baseName, index: index,
                    newIndex: i,
                    valueAtIndex: valueAtIndex,
                    globalIndex: globalIndex)
                // Always reconcile visual state (NSButton's radio click may have left siblings
                // out of sync if we returned early in a previous click handler).
                let onIndex: Int
                switch decision {
                case .skip:
                    onIndex = Preferences.hasOverride(baseName, index)
                        ? (Int(UserDefaults.standard.string(forKey: key) ?? "") ?? -1)
                        : globalIndex()
                case .write:
                    onIndex = i
                }
                for (j, b) in buttons.enumerated() { b.state = (j == onIndex) ? .on : .off }
                if case .write = decision { onChange() }
            }
        }
    }

    private static func installOverrideSwitchAction(
        _ control: Switch,
        baseName: String,
        index: Int,
        onChange: @escaping () -> Void
    ) {
        let key = Preferences.indexToName(baseName, index)
        control.onAction = { c in
            let sw = c as! Switch
            // Toggling always changes state, so there's no "same-value click" case to detect.
            // Always write the override.
            Preferences.set(key, sw.state == .on ? "true" : "false")
            onChange()
        }
    }

    /// Resnap an override control's displayed value to the current global, without firing a write
    /// (so no override key is created). Used after `removeOverride` and after a global value changes.
    /// For Pro-gated segments (Size / ShortcutStyle), also refreshes the badge overlay — without
    /// this, the badge's icon/label colors stay frozen at their pre-resnap state, so an unlinked
    /// "Search" segment keeps its selected white-on-blue look even after the selection moves to
    /// "Focus".
    private static func syncOverrideControlToGlobal(_ baseName: String, _ index: Int) {
        let key = Preferences.indexToName(baseName, index)
        guard let control = overrideControls[key] else { return }
        switch baseName {
        case "appearanceStyleOverride":
            syncRadioButtons(control, to: Preferences.appearanceStyle.index)
        case "appearanceSizeOverride":
            if let segmented = control as? NSSegmentedControl {
                segmented.selectedSegment = Preferences.appearanceSize.index
                if let overlay = overrideProBadges[key] {
                    AppearanceTab.refreshTrailingSegmentBadge(segmented, proIndex: AppearanceSizePreference.allCases.firstIndex(of: .auto)!, overlay: overlay)
                }
            }
        case "appearanceThemeOverride":
            (control as? NSSegmentedControl)?.selectedSegment = Preferences.appearanceTheme.index
        case "shortcutStyleOverride":
            if let segmented = control as? NSSegmentedControl {
                segmented.selectedSegment = Preferences.shortcutStyle.index
                if let overlay = overrideProBadges[key] {
                    AppearanceTab.refreshTrailingSegmentBadge(segmented, proIndex: ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!, overlay: overlay)
                }
            }
        case "previewFocusedWindowOverride":
            (control as? Switch)?.setSilently(Preferences.previewSelectedWindow ? .on : .off)
        default: break
        }
    }

    /// Resnap the 3 Pro-gated index-0 override controls to their currently-stored UserDefaults value.
    /// Used after a Pro lock/unlock transition: `ProTransitionState.onProLockEngaged` writes
    /// `appearanceStyleOverride` / etc. to the free equivalent, but the segmented/radio controls
    /// still hold the user's pre-lock selection. Reading from UserDefaults catches them up.
    private static func refreshGatedOverrideControlsFromStored() {
        let styleKey = Preferences.indexToName("appearanceStyleOverride", 0)
        if let style = overrideControls[styleKey] {
            let stored = CachedUserDefaults.intFromMacroPref(styleKey, AppearanceStylePreference.allCases)
            syncRadioButtons(style, to: stored)
        }
        let sizeKey = Preferences.indexToName("appearanceSizeOverride", 0)
        if let size = overrideControls[sizeKey] as? NSSegmentedControl {
            size.selectedSegment = CachedUserDefaults.intFromMacroPref(sizeKey, AppearanceSizePreference.allCases)
            if let overlay = overrideProBadges[sizeKey] {
                AppearanceTab.refreshTrailingSegmentBadge(size, proIndex: AppearanceSizePreference.allCases.firstIndex(of: .auto)!, overlay: overlay)
            }
        }
        let shortcutStyleKey = Preferences.indexToName("shortcutStyleOverride", 0)
        if let shortcutStyle = overrideControls[shortcutStyleKey] as? NSSegmentedControl {
            shortcutStyle.selectedSegment = CachedUserDefaults.intFromMacroPref(shortcutStyleKey, ShortcutStylePreference.allCases)
            if let overlay = overrideProBadges[shortcutStyleKey] {
                AppearanceTab.refreshTrailingSegmentBadge(shortcutStyle, proIndex: ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!, overlay: overlay)
            }
        }
    }

    /// Iterate every override control and resnap the ones whose key isn't overridden to the global.
    /// Called from `preferenceChanged` when a global appearance setting changes.
    static func syncOverrideControlsToGlobal() {
        for baseName in Preferences.appearanceOverrideBaseNames {
            for index in 0...Preferences.maxShortcutCount {
                if !Preferences.hasOverride(baseName, index) {
                    syncOverrideControlToGlobal(baseName, index)
                }
            }
        }
    }

    /// Show/hide each unlink button based on `hasOverride` for its key. Called after any override
    /// or global change so the link/unlink affordance stays accurate.
    private static func refreshUnlinkButtons() {
        for (key, button) in unlinkButtons {
            guard let (baseName, index) = parseOverrideKey(key) else { continue }
            let shouldBeHidden = !Preferences.hasOverride(baseName, index)
            if button.isHidden != shouldBeHidden {
                button.isHidden = shouldBeHidden
            }
        }
    }

    private static func parseOverrideKey(_ key: String) -> (String, Int)? {
        for baseName in Preferences.appearanceOverrideBaseNames {
            for i in 0...Preferences.maxShortcutCount {
                if Preferences.indexToName(baseName, i) == key { return (baseName, i) }
            }
        }
        return nil
    }

    private static func isOverrideKey(_ key: String) -> Bool {
        parseOverrideKey(key) != nil
    }

    private static func syncRadioButtons(_ view: NSView, to index: Int) {
        guard let stack = view as? NSStackView else { return }
        for (i, subview) in stack.arrangedSubviews.enumerated() {
            if let buttonView = subview as? ImageTextButtonView {
                buttonView.state = i == index ? .on : .off
            } else if let button = subview as? NSButton {
                button.state = i == index ? .on : .off
            }
        }
    }

    /// Called by `AppearanceTab.overrideInfoClicked` to deep-link from the global appearance row's
    /// "Overridden in Shortcut: N" button. Selects the shortcut and switches the editor to the
    /// Appearance segment.
    static func selectShortcutAndShowAppearance(_ index: Int) {
        selectedTabSegment = 1
        selectShortcut(index)
        // Apply tab selection to all shortcut editors so the appearance section is visible.
        for (_, contents) in tabContentsByIndex {
            contents.tabControl.selectedSegment = selectedTabSegment
            for (i, pane) in contents.panes.enumerated() {
                pane.isHidden = selectedTabSegment != i
            }
        }
    }

    private static func refreshShortcutControlsDisplay() {
        shortcutControls.values.forEach {
            $0.0.needsDisplay = true
            $0.0.invalidateIntrinsicContentSize()
        }
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
        setHoveredShortcutRow(nil)
        clearArrangedSubviews(rows)
        shortcutRows.removeAll(keepingCapacity: true)
        for index in 0..<Preferences.shortcutCount {
            let row = SidebarListRow()
            row.setContent(shortcutTitle(index), shortcutSummary(index))
            row.setSelected(index == selectedShortcutIndex && selectedShortcutIndex != gestureSelectionIndex)
            if index >= 1 {
                row.setProBadge(true)
            }
            row.onClick = { _, _ in
                selectShortcut(index)
            }
            row.onMouseEntered = { _, view in setHoveredShortcutRow(view as? SidebarListRow) }
            row.onMouseExited = { _, _ in setHoveredShortcutRow(nil) }
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: sidebarRowHeight).isActive = true
            shortcutRows.append(row)
            if index < Preferences.shortcutCount - 1 {
                let separator = sidebarSeparatorView()
                rows.addArrangedSubview(separator)
                separator.leadingAnchor.constraint(equalTo: rows.leadingAnchor, constant: TableGroupView.padding).isActive = true
                separator.trailingAnchor.constraint(equalTo: rows.trailingAnchor, constant: -TableGroupView.padding).isActive = true
                separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
            }
        }
        syncShortcutSidebarHoverState()
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
        if currentCount >= 1 && LicenseManager.shared.isProLocked {
            UpgradeTab.navigateToUpgradeTab()
            return
        }
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
        Preferences.setShortcut(Preferences.indexToName("holdShortcut", index), keyEquivalent: "⌥", false)
        Preferences.setShortcut(Preferences.indexToName("nextWindowShortcut", index), keyEquivalent: "", false)
        Preferences.set(Preferences.indexToName("appsToShow", index), AppsToShowPreference.all.indexAsString, false)
    }

    private static func copyShortcutPreferences(_ fromIndex: Int, _ toIndex: Int) {
        removableShortcutPreferences.forEach { baseName in
            let fromKey = Preferences.indexToName(baseName, fromIndex)
            let toKey = Preferences.indexToName(baseName, toIndex)
            if let value = UserDefaults.standard.object(forKey: fromKey) {
                UserDefaults.standard.set(value, forKey: toKey)
                CachedUserDefaults.removeFromCache(toKey)
                Preferences.invalidateAllCache()
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
        control.objectValue = Preferences.shortcut(controlId)
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
        let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", index))?.keyEquivalent ?? ""
        let nextWindowShortcut = Preferences.shortcut(Preferences.indexToName("nextWindowShortcut", index))?.keyEquivalent ?? ""
        if nextWindowShortcut.isEmpty {
            return holdShortcut
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

    private static func installShortcutSidebarHoverObserver(_ scrollView: NSScrollView) {
        if let shortcutRowsScrollObserver {
            NotificationCenter.default.removeObserver(shortcutRowsScrollObserver)
        }
        shortcutRowsScrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { _ in
            syncShortcutSidebarHoverState()
        }
    }

    private static func setHoveredShortcutRow(_ row: SidebarListRow?) {
        shortcutRows.forEach { $0.setHovered($0 === row) }
        if let gestureSidebarRow {
            gestureSidebarRow.setHovered(gestureSidebarRow === row)
        }
    }

    private static func syncShortcutSidebarHoverState() {
        guard let shortcutRowsScrollView else { return }
        setHoveredShortcutRow(hoveredShortcutRowAtCursor(shortcutRowsScrollView))
    }

    private static func hoveredShortcutRowAtCursor(_ scrollView: NSScrollView) -> SidebarListRow? {
        guard let window = scrollView.window else { return nil }
        let cursorInScrollView = scrollView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard scrollView.bounds.contains(cursorInScrollView) else { return nil }
        guard let documentView = scrollView.documentView else { return nil }
        let cursorInDocumentView = documentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return enclosingSidebarListRow(documentView.hitTest(cursorInDocumentView))
    }

    private static func enclosingSidebarListRow(_ view: NSView?) -> SidebarListRow? {
        var current = view
        while let candidate = current {
            if let row = candidate as? SidebarListRow {
                return row
            }
            current = candidate.superview
        }
        return nil
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
        SettingsWindow.shared.beginSheetWithSearchHighlight(shortcutsWhenActiveSheet)
    }

    @objc static func showAdditionalControlsSettings() {
        SettingsWindow.shared.beginSheetWithSearchHighlight(additionalControlsSheet)
    }

    private static func addShortcut(_ triggerPhase: ShortcutTriggerPhase, _ scope: ShortcutScope, _ shortcut: Shortcut, _ controlId: String, _ index: Int?) {
        let atShortcut = ATShortcut(shortcut, controlId, scope, triggerPhase, index)
        removeShortcutIfExists(controlId)
        shortcuts[controlId] = atShortcut
        if scope == .global {
            KeyboardEvents.addGlobalShortcut(controlId, atShortcut.shortcut)
            ControlsTab.toggleNativeCommandTabIfNeeded()
        }
        recomputeEscapeAbsorption()
    }

    /// Issue #5585. The shared cghidEventTap absorbs Esc keyDown only when a configured shortcut
    /// binds Escape; otherwise Esc passes through to the active app unchanged.
    static func recomputeEscapeAbsorption() {
        KeyboardEvents.anyShortcutUsesEscape = shortcuts.values.contains { $0.shortcut.carbonKeyCode == kVK_Escape }
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
            guard let shortcut = Preferences.shortcut(controlId) else {
                removeShortcutIfExists(controlId)
                return
            }
            addShortcut(.up, .global, shortcut, controlId, i)
            if let nextWindowShortcut = shortcutControls[Preferences.indexToName("nextWindowShortcut", i)]?.0 {
                nextWindowShortcut.restrictModifiers([(sender as! CustomRecorderControl).objectValue!.modifierFlags])
                shortcutChangedCallback(nextWindowShortcut)
            }
        } else {
            let newShortcut = combineHoldAndNextWindow(controlId, sender)
            if newShortcut == nil {
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

    static func combineHoldAndNextWindow(_ controlId: String, _ sender: NSControl) -> Shortcut? {
        guard let baseShortcut = (sender as! RecorderControl).objectValue else { return nil }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId)))
            return combineShortcuts(holdShortcut, baseShortcut)
        }
        return baseShortcut
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        if (sender as! Switch).state == .on {
            if isClearArrowKeysSuccessful() {
                arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
            } else {
                (sender as! Switch).state = .off
                Preferences.set("arrowKeysEnabled", "false", false)
            }
        } else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
        }
    }

    private static func isClearArrowKeysSuccessful() -> Bool {
        var conflicts = [String: String]()
        shortcuts.forEach {
            guard arrowKeyCodes.contains($1.shortcut.keyCode) else { return }
            guard !arrowKeys.contains($1.id) else { return }
            if let label = conflictLabel($1.id) {
                conflicts[$1.id] = label
            }
        }
        if !conflicts.isEmpty {
            if SettingsWindow.shared == nil || !shouldClearConflictingShortcuts(conflicts.map { $0.value }, NSLocalizedString("Arrow keys already assigned to other actions:\n%@", comment: "")) {
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
            if SettingsWindow.shared == nil || !shouldClearConflictingShortcuts(conflicts.map { $0.value }, NSLocalizedString("Vim keys already assigned to other actions:\n%@", comment: "")) {
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

    private static func shouldClearConflictingShortcuts(_ conflicts: [String], _ messageFormat: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        let informativeText = conflicts.map { "• " + $0 }.joined(separator: "\n")
        alert.informativeText = String(format: messageFormat, informativeText.replacingOccurrences(of: " ", with: "\u{00A0}"))
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
            recomputeEscapeAbsorption()
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
        guard let shortcut = combinedShortcut(controlId) else {
            removeShortcutIfExists(controlId)
            restrictModifiersOfHoldShortcut(controlId, [])
            return
        }
        addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, shortcut, controlId, nil)
        restrictModifiersOfHoldShortcut(controlId, [shortcut.modifierFlags])
    }

    private static func applyHoldShortcutPreference(_ controlId: String) {
        let i = Preferences.nameToIndex(controlId)
        guard let shortcut = Preferences.shortcut(controlId) else {
            removeShortcutIfExists(controlId)
            return
        }
        addShortcut(.up, .global, shortcut, controlId, i)
    }

    private static func combinedShortcut(_ controlId: String) -> Shortcut? {
        guard let baseShortcut = Preferences.shortcut(controlId) else { return nil }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", Preferences.nameToIndex(controlId)))
            return combineShortcuts(holdShortcut, baseShortcut)
        }
        return baseShortcut
    }

    private static func combineShortcuts(_ holdShortcut: Shortcut?, _ baseShortcut: Shortcut) -> Shortcut {
        guard let holdShortcut else { return baseShortcut }
        return Shortcut(code: baseShortcut.keyCode, modifierFlags: [holdShortcut.modifierFlags, baseShortcut.modifierFlags], characters: baseShortcut.characters, charactersIgnoringModifiers: baseShortcut.charactersIgnoringModifiers)
    }

    private static func applyArrowKeysPreferenceWithoutDialogs() {
        guard Preferences.arrowKeysEnabled else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
            return
        }
        if hasArrowKeysConflictWithoutUi() {
            arrowKeys.forEach { removeShortcutIfExists($0) }
            Preferences.set("arrowKeysEnabled", "false", false)
            return
        }
        arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
    }

    private static func hasArrowKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            guard arrowKeyCodes.contains($0.shortcut.keyCode) else { return false }
            return !arrowKeys.contains($0.id)
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

}
