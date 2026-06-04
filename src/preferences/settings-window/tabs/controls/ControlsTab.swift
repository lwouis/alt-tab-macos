import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

/// Coordinator for the Controls section.
///
/// Owns the shortcut sidebar (list of shortcuts + the gesture row + count buttons), one recycled
/// `ShortcutEditor` (re-bound across shortcuts 0..N-1 as the user picks rows), and a fixed-bind
/// editor view for the gesture. Also keeps the global shortcut-registry logic (`shortcuts` dict,
/// `addShortcut` / `removeShortcutIfExists` / `applyShortcutPreference`) and the arrow/vim helper
/// callbacks consumed by other modules.
class ControlsTab {
    // MARK: - Public runtime state consumed by other modules

    /// Runtime model of all globally-bound shortcuts, keyed by their identifier
    /// (`holdShortcut0`, `nextWindowShortcut2`, etc.). Driven by `applyShortcutPreference`.
    /// Read by KeyboardEvents, KeyRepeatTimer, ATShortcut, TilesView, CustomRecorderControl,
    /// and the conflict detectors.
    static var shortcuts = [String: ATShortcut]()

    /// UI lookup: for any recorder currently displayed in Settings, its (control, label string).
    /// Populated by `TriggerBinding.bind` and by `LabelAndControl.makeLabelWithRecorder` (used in
    /// the always-displayed sheets). With the recycled editor we only keep entries for the
    /// currently-bound shortcut; operations on other shortcuts go through `Preferences` directly.
    static var shortcutControls = [String: (CustomRecorderControl, String)]()

    static var arrowKeysCheckbox: Switch!
    static var vimKeysCheckbox: Switch!

    static var shortcutsWhenActiveSheet: ShortcutsWhenActiveSheet!
    static var additionalControlsSheet: AdditionalControlsSheet!

    /// Map from a tab-segment `NSSegmentedControl` (Filtering / Appearance / Ordering) to the
    /// per-segment list of searchable strings. Consulted by
    /// `SettingsWindow.highlightTarget(_ segmentedControl:)` to bubble a search match into the
    /// parent segment so a query that targets a (possibly unbuilt — see lazy panes) pane lights
    /// up the corresponding tab segment yellow. Two entries today: one for the shortcut editor's
    /// tab control, one for the gesture editor's tab control.
    static var tabSegmentSearchableStrings = [ObjectIdentifier: [[String]]]()

    // MARK: - Layout constants (unchanged from the old monolithic editor)

    private static let shortcutSidebarWidth = CGFloat(180)
    private static let sidebarRowHeight = CGFloat(52)
    private static let sidebarHorizontalPadding = TableGroupView.padding
    private static let shortcutEditorTopBottomPadding = TableGroupView.padding
    private static let shortcutEditorRightPadding = TableGroupView.padding
    private static var shortcutEditorWidth: CGFloat { SettingsWindow.contentWidth - shortcutSidebarWidth - 1 }
    static var shortcutEditorContentWidth: CGFloat { shortcutEditorWidth - shortcutEditorRightPadding }
    private static let gestureSelectionIndex = -1
    private static let staticManagedShortcutPreferences = [
        "focusWindowShortcut", "previousWindowShortcut", "cancelShortcut", "searchShortcut", "lockSearchShortcut",
        "closeWindowShortcut", "minDeminWindowShortcut", "toggleFullscreenWindowShortcut", "quitAppShortcut", "hideShowAppShortcut",
    ]
    /// Canonical id → localized label for the always-active ("when active") shortcuts. Single source
    /// of truth: `ShortcutsWhenActiveSheet` reads its row titles from here, and `conflictLabel(_:)`
    /// uses it to name a conflicting shortcut without needing its (possibly-unbuilt) sheet control.
    static let staticShortcutLabels = [
        "focusWindowShortcut": NSLocalizedString("Focus selected window", comment: ""),
        "previousWindowShortcut": NSLocalizedString("Select previous window", comment: ""),
        "cancelShortcut": NSLocalizedString("Cancel", comment: ""),
        "searchShortcut": NSLocalizedString("Search", comment: ""),
        "lockSearchShortcut": NSLocalizedString("Lock search", comment: ""),
        "closeWindowShortcut": NSLocalizedString("Close window", comment: ""),
        "minDeminWindowShortcut": NSLocalizedString("Minimize/Deminimize window", comment: ""),
        "toggleFullscreenWindowShortcut": NSLocalizedString("Fullscreen/Defullscreen window", comment: ""),
        "quitAppShortcut": NSLocalizedString("Quit app", comment: ""),
        "hideShowAppShortcut": NSLocalizedString("Hide/Show app", comment: ""),
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
    private static let arrowKeys = ["←", "→", "↑", "↓"]
    private static let arrowKeyCodes: Set<KeyCode> = [.leftArrow, .rightArrow, .upArrow, .downArrow]
    private static let vimKeyActions = [
        "h": "vimCycleLeft",
        "l": "vimCycleRight",
        "k": "vimCycleUp",
        "j": "vimCycleDown",
    ]

    // MARK: - Editor + sidebar state

    private static var editor: ShortcutEditor!
    private static var gestureEditorView: NSView?
    private static var gestureEditorTabControl: NSSegmentedControl?
    /// Outer container of the gesture editor — used by `ensureGesturePaneBuilt` to append a pane
    /// to it the first time the user selects that segment. Kept weak via the static-let pattern
    /// (cleared in `cleanup()`).
    private static var gestureEditorContainer: NSStackView?
    private static var gestureFilteringPane: FilteringPane?
    private static var gestureAppearancePane: AppearancePane?
    private static var gestureOrderingPane: OrderingPane?
    private static var selectedShortcutIndex = 0
    private static var shortcutRowsStackView: NSStackView?
    private static var shortcutRows = [SidebarListRow]()
    private static var gestureSidebarRow: SidebarListRow?
    private static var shortcutCountButtons: NSSegmentedControl?
    private static var shortcutRowsScrollView: NSScrollView?
    private static var shortcutRowsScrollObserver: NSObjectProtocol?
    private static var proLockObserver: NSObjectProtocol?

    // MARK: - Initialization / teardown

    static func initializePreferencesDependentState() {
        applyActiveShortcutPreferences()
        staticManagedShortcutPreferences.forEach { applyShortcutPreference($0) }
        applyArrowKeysPreferenceWithoutDialogs()
        applyVimKeysPreferenceWithoutDialogs()
    }

    static func initTab() -> NSView {
        editor = ShortcutEditor(width: shortcutEditorContentWidth)
        let shortcutEntry = editor.tabSegmentSearchableStringsEntry
        tabSegmentSearchableStrings[shortcutEntry.key] = shortcutEntry.perSegmentStrings

        gestureEditorView = makeGestureEditor()

        let shortcutsView = makeShortcutsView()
        let additionalControlsButton = NSButton(title: NSLocalizedString("Additional controls…", comment: ""), target: self, action: #selector(showAdditionalControlsSettings))
        let shortcutsButton = NSButton(title: NSLocalizedString("Shortcuts when active…", comment: ""), target: self, action: #selector(showShortcutsSettings))
        let tools = StackView([additionalControlsButton, shortcutsButton], .horizontal)
        let view = TableGroupSetView(originalViews: [shortcutsView], toolsViews: [tools], padding: 0, bottomPadding: 0, othersAlignment: .leading, toolsAlignment: .trailing)

        // Sheets are built lazily on first show. Pre-build search visibility is provided by
        // their static `searchableStrings`, consulted through `SettingsSearchIndex`.

        refreshShortcutUi()
        let initialBindIndex = (selectedShortcutIndex == gestureSelectionIndex) ? 0 : selectedShortcutIndex
        editor.bind(toShortcut: initialBindIndex)
        (0..<Preferences.shortcutCount).forEach { initializeShortcutRecorderState($0) }

        if proLockObserver == nil {
            proLockObserver = NotificationCenter.default.addObserver(
                forName: ProTransitionManager.proLockStateDidChangeNotification,
                object: nil, queue: .main
            ) { _ in
                refreshShortcutUi()
                editor?.refreshFromCurrentBind()
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
        shortcutsWhenActiveSheet = nil
        additionalControlsSheet = nil
        arrowKeysCheckbox = nil
        vimKeysCheckbox = nil
        shortcutControls.removeAll()
        shortcutRows.removeAll()
        tabSegmentSearchableStrings.removeAll()
        editor = nil
        gestureEditorView = nil
        gestureEditorTabControl = nil
        gestureEditorContainer = nil
        gestureFilteringPane = nil
        gestureAppearancePane = nil
        gestureOrderingPane = nil
        shortcutRowsStackView = nil
        gestureSidebarRow = nil
        shortcutCountButtons = nil
        shortcutRowsScrollView = nil
    }

    // MARK: - Preference-change routing

    static func preferenceChanged(_ key: String) {
        switch key {
        case "shortcutCount":
            applyActiveShortcutPreferences()
            (0..<Preferences.shortcutCount).forEach { initializeShortcutRecorderState($0) }
            refreshShortcutUi()
        case "nextWindowGesture":
            refreshGestureRow()
        case let k where isShortcutPreferenceKey(k):
            let i = Preferences.nameToIndex(k)
            if i < Preferences.shortcutCount {
                // If the changed key targets the currently-bound editor, refresh it so the
                // recorder displays the new value. Otherwise the value lives in Preferences and
                // doesn't need any UI work.
                if i == selectedShortcutIndex { editor?.refreshFromCurrentBind() }
                applyShortcutPreference(k)
            } else {
                removeShortcutIfExists(k)
            }
            refreshShortcutRows()
        case let k where staticManagedShortcutPreferences.contains(k):
            applyShortcutPreference(k)
        case let k where Preferences.overrideToGlobalKey.values.contains(k):
            // A global appearance setting changed; resnap non-overridden controls in the editor
            // and refresh AppearanceTab's "Overridden in Shortcut:" labels.
            editor?.refreshFromCurrentBind()
            AppearanceTab.refreshAllOverrideInfoLabels()
        case let k where isOverrideKey(k):
            // An override key changed (e.g. user picked a different value, or remembered-restore wrote).
            editor?.refreshFromCurrentBind()
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

    /// Called by AppearanceTab when a global appearance pref changes.
    /// In the new design this is equivalent to a no-arg refresh of the current editor binding.
    static func syncOverrideControlsToGlobal() {
        editor?.refreshFromCurrentBind()
    }

    /// Deep-link from AppearanceTab's "Overridden in Shortcut: N" button — select the shortcut and
    /// switch the editor to the Appearance segment.
    static func selectShortcutAndShowAppearance(_ index: Int) {
        selectShortcut(index)
        editor?.showAppearanceSegment()
    }

    // MARK: - Editor swap based on sidebar selection

    private static func showEditor(forShortcut: Bool) {
        editor?.view.isHidden = !forShortcut
        gestureEditorView?.isHidden = forShortcut
        if !forShortcut {
            // The gesture editor's tabControl + pane visibility may have drifted out of sync
            // while it was hidden (user switched tabs on the shortcut editor in the meantime).
            // Resync from the shared `ShortcutEditor.selectedTabSegment` before showing it.
            syncGestureEditorTabSegment()
        }
    }

    private static func syncGestureEditorTabSegment() {
        guard let tabControl = gestureEditorTabControl else { return }
        let segment = ShortcutEditor.selectedTabSegment
        tabControl.selectedSegment = segment
        ensureGesturePaneBuilt(forSegment: segment)
    }

    // MARK: - Sidebar + container view

    private static func makeShortcutsView() -> NSView {
        return makeSidebarEditorContainer(sidebar: makeShortcutSidebar(), editor: makeEditorPane())
    }

    private static func makeEditorPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(equalToConstant: shortcutEditorWidth).isActive = true
        var views: [NSView] = [editor.view]
        if let gestureEditorView { views.append(gestureEditorView) }
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
        // Start the recycled row pool empty and bound to this freshly-built stack view;
        // `refreshShortcutRows` grows it on demand. (`cleanup` also clears it on window close.)
        shortcutRows.removeAll()
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

    // MARK: - Gesture editor

    /// Fixed-bind editor for the gesture. Same shape as the shortcut editor (Filtering /
    /// Appearance / Ordering panes), but with a single dropdown for the gesture trigger and bound
    /// permanently to `Preferences.gestureIndex`. Built once, never rebinds.
    private static func makeGestureEditor() -> NSView {
        let message = NSLocalizedString("You may need to disable some conflicting system gestures", comment: "")
        let openTrackpad = NSButton(title: NSLocalizedString("Open Trackpad Settings…", comment: ""), target: self, action: #selector(openSystemGestures(_:)))
        let infoBtn = LabelAndControl.makeInfoButton(searchableTooltipTexts: [message], onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: message, extraView: openTrackpad)
        })
        let gestureDropdown = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
        let triggerContent = NSStackView()
        triggerContent.orientation = .horizontal
        triggerContent.alignment = .centerY
        triggerContent.setViews([gestureDropdown], in: .trailing)
        triggerContent.setViews([infoBtn], in: .leading)
        triggerContent.heightAnchor.constraint(equalToConstant: ShortcutEditor.triggerRowContentHeight).isActive = true

        let width = shortcutEditorContentWidth
        let triggerTable = TableGroupView(width: width)
        triggerTable.addRow(TableGroupView.Row(leftTitle: ShortcutEditor.triggerLabel, rightViews: [triggerContent]))

        // Section-level search registration: every pane's static strings go into the active
        // SettingsSearchIndex even though we haven't built the panes yet. This keeps the
        // Exceptions section searchable for pane content before the user has ever opened the
        // gesture editor.
        SettingsSearchIndex.registerStrings(FilteringPane.searchableStrings)
        SettingsSearchIndex.registerStrings(AppearancePane.searchableStrings)
        SettingsSearchIndex.registerStrings(OrderingPane.searchableStrings)

        let labels = [
            ShortcutEditor.tabLabelFiltering,
            ShortcutEditor.tabLabelAppearance,
            ShortcutEditor.tabLabelOrdering,
        ]
        let tabControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        tabControl.selectedSegment = ShortcutEditor.selectedTabSegment
        LabelAndControl.applySystemSelectedSegmentStyle(tabControl)
        tabControl.widthAnchor.constraint(equalToConstant: width).isActive = true
        let segmentWidth = width / CGFloat(labels.count)
        for i in 0..<labels.count { tabControl.setWidth(segmentWidth, forSegment: i) }
        tabControl.onAction = { [weak tabControl] _ in
            guard let tabControl else { return }
            let seg = tabControl.selectedSegment
            ShortcutEditor.selectedTabSegment = seg
            ensureGesturePaneBuilt(forSegment: seg)
            // Keep the shortcut editor's tab in sync — the user expects sidebar navigation
            // between shortcuts/gesture to preserve their tab choice.
            editor?.applySelectedSegment(seg)
        }
        tabSegmentSearchableStrings[ObjectIdentifier(tabControl)] = [
            FilteringPane.searchableStrings,
            AppearancePane.searchableStrings,
            OrderingPane.searchableStrings,
        ]
        gestureEditorTabControl = tabControl

        // No `contentMinHeight` constraint here — the gesture editor sizes itself naturally —
        // so we can use plain `addArrangedSubview` without the gravity-area workarounds that
        // `ShortcutEditor` needs for its min-height constraint.
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = TableGroupSetView.tableGroupSpacing
        container.addArrangedSubview(triggerTable)
        container.addArrangedSubview(tabControl)
        container.setCustomSpacing(10, after: triggerTable)
        gestureEditorContainer = container

        // Build the initially-selected pane so the editor isn't empty when first shown.
        ensureGesturePaneBuilt(forSegment: ShortcutEditor.selectedTabSegment)
        return container
    }

    private static func ensureGesturePaneBuilt(forSegment segment: Int) {
        let width = shortcutEditorContentWidth
        switch segment {
        case 0:
            if gestureFilteringPane == nil {
                let pane = FilteringPane(width: width)
                pane.bind(toShortcut: Preferences.gestureIndex)
                gestureEditorContainer?.addArrangedSubview(pane.view)
                gestureFilteringPane = pane
            }
        case 1:
            if gestureAppearancePane == nil {
                let pane = AppearancePane(width: width)
                pane.bind(toShortcut: Preferences.gestureIndex)
                gestureEditorContainer?.addArrangedSubview(pane.view)
                gestureAppearancePane = pane
            }
        case 2:
            if gestureOrderingPane == nil {
                let pane = OrderingPane(width: width)
                pane.bind(toShortcut: Preferences.gestureIndex)
                gestureEditorContainer?.addArrangedSubview(pane.view)
                gestureOrderingPane = pane
            }
        default: break
        }
        gestureFilteringPane?.view.isHidden = segment != 0
        gestureAppearancePane?.view.isHidden = segment != 1
        gestureOrderingPane?.view.isHidden = segment != 2
    }

    // MARK: - Selection

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
        let count = Preferences.shortcutCount
        clearArrangedSubviews(rows)
        // Recycle the row instances: grow/shrink the pool to `count`, creating new `SidebarListRow`s
        // only when the count actually increases. Reusing instances avoids rebuilding the
        // label/observer machinery on every refresh (this runs on +/- clicks, recorder edits,
        // input-source changes, and the pro-lock observer). The search index is re-published below
        // regardless, so added/removed rows stay correct.
        while shortcutRows.count < count {
            shortcutRows.append(makeShortcutRow(index: shortcutRows.count))
        }
        if shortcutRows.count > count {
            shortcutRows.removeLast(shortcutRows.count - count)
        }
        for index in 0..<count {
            let row = shortcutRows[index]
            row.setContent(shortcutTitle(index), shortcutSummary(index))
            row.setSelected(index == selectedShortcutIndex && selectedShortcutIndex != gestureSelectionIndex)
            row.setProBadge(index >= 1)
            rows.addArrangedSubview(row)
            // Re-create the row↔stack width constraint each layout: AppKit drops it when the row is
            // removed from the stack by `clearArrangedSubviews`. The row's height constraint is
            // row-internal, set once in `makeShortcutRow`, and survives the remove/re-add cycle.
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            if index < count - 1 {
                let separator = sidebarSeparatorView()
                rows.addArrangedSubview(separator)
                separator.leadingAnchor.constraint(equalTo: rows.leadingAnchor, constant: TableGroupView.padding).isActive = true
                separator.trailingAnchor.constraint(equalTo: rows.trailingAnchor, constant: -TableGroupView.padding).isActive = true
                separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
            }
        }
        syncShortcutSidebarHoverState()
        // The rows were (re)built outside the section's build-time `indexed { }` scope, so their own
        // `registerSearchContent` can't reach an active builder. Ask the window to re-publish the
        // Controls section's dynamic search content from the current rows so a "sho" query keeps
        // highlighting them. No-ops until `SettingsWindow.shared` is set (initial build is covered
        // by `SettingsWindow.setupView`).
        SettingsWindow.shared?.refreshSectionSearchContent("controls")
    }

    private static func makeShortcutRow(index: Int) -> SidebarListRow {
        let row = SidebarListRow()
        row.onClick = { _, _ in selectShortcut(index) }
        row.onMouseEntered = { _, view in setHoveredShortcutRow(view as? SidebarListRow) }
        row.onMouseExited = { _, _ in setHoveredShortcutRow(nil) }
        row.heightAnchor.constraint(equalToConstant: sidebarRowHeight).isActive = true
        return row
    }

    private static func refreshShortcutSelection() {
        shortcutRows.enumerated().forEach { $1.setSelected($0 == selectedShortcutIndex) }
        gestureSidebarRow?.setSelected(selectedShortcutIndex == gestureSelectionIndex)
        if selectedShortcutIndex == gestureSelectionIndex {
            showEditor(forShortcut: false)
        } else {
            editor?.bind(toShortcut: selectedShortcutIndex)
            showEditor(forShortcut: true)
        }
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

    // MARK: - Shortcut row content (title + summary)

    private static func shortcutTitle(_ index: Int) -> String {
        return NSLocalizedString("Shortcut", comment: "") + " " + String(index + 1)
    }

    private static func shortcutSummary(_ index: Int) -> String {
        let holdShortcut = Preferences.shortcut(Preferences.indexToName("holdShortcut", index))?.keyEquivalent ?? ""
        let nextWindowShortcut = Preferences.shortcut(Preferences.indexToName("nextWindowShortcut", index))?.keyEquivalent ?? ""
        if nextWindowShortcut.isEmpty { return holdShortcut }
        return holdShortcut + " + " + nextWindowShortcut
    }

    /// Refresh just the sidebar row's title + summary for one shortcut index. Called by the
    /// recycled `TriggerBinding` after the user edits a recorder so the sidebar reflects the
    /// new modifier + key combo immediately, without rebuilding the whole sidebar.
    static func refreshShortcutRowContent(forIndex index: Int) {
        guard index >= 0, index < shortcutRows.count else { return }
        shortcutRows[index].setContent(shortcutTitle(index), shortcutSummary(index))
    }

    private static func gestureTitle() -> String { NSLocalizedString("Gesture", comment: "") }
    private static func gestureSummary() -> String { Preferences.nextWindowGesture.localizedString }

    private static func refreshGestureRow() {
        guard let gestureSidebarRow else { return }
        gestureSidebarRow.setContent(gestureTitle(), gestureSummary())
        gestureSidebarRow.setSelected(selectedShortcutIndex == gestureSelectionIndex)
    }

    /// Register the current sidebar rows (the shortcut rows + the persistent gesture row) into the
    /// active search-index builder. Invoked by `SettingsWindow.refreshSectionSearchContent("controls")`
    /// inside a fresh `indexed { }` scope — at build time and after every `refreshShortcutRows`. The
    /// rows can't self-register at creation because they're (re)built outside the build scope; this
    /// is the single place that publishes them, so a "sho" query lights up "Shortcut 1"/"Shortcut 2"
    /// and "Gesture". Targets read the labels' `stringValue` live, so in-place content edits don't
    /// need re-registration.
    static func registerSidebarRowsSearchContent() {
        shortcutRows.forEach { $0.registerSearchContent() }
        gestureSidebarRow?.registerSearchContent()
    }

    // MARK: - Hover state

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
            if let row = candidate as? SidebarListRow { return row }
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

    // MARK: - Override key helpers (still needed for preferenceChanged routing)

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

    private static func isShortcutPreferenceKey(_ key: String) -> Bool {
        return (0..<Preferences.maxShortcutCount).contains(where: { index in
            ["holdShortcut", "nextWindowShortcut"].contains { key == Preferences.indexToName($0, index) }
        })
    }

    // MARK: - Shortcut registry (global keyboard binding — unchanged from the old code)

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
        if shortcutsWhenActiveSheet == nil { shortcutsWhenActiveSheet = ShortcutsWhenActiveSheet() }
        SettingsWindow.shared.beginSheetWithSearchHighlight(shortcutsWhenActiveSheet)
    }

    @objc static func showAdditionalControlsSettings() {
        if additionalControlsSheet == nil { additionalControlsSheet = AdditionalControlsSheet() }
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

    /// Thin adapter over `NativeHotkeyResolver.resolve` — builds the snapshot inputs from the live
    /// shortcut registry and applies the resolver's verdict via the symbolic-hotkey API. See
    /// `NativeHotkeyResolverSpecs.md` for the kernel's invariants and #5653's root cause.
    static func toggleNativeCommandTabIfNeeded() {
        let snapshots = shortcuts.values.map { ShortcutSnapshot(modifiers: $0.shortcut.carbonModifierFlags, keyCode: $0.shortcut.carbonKeyCode) }
        let holdShortcutModifiers: [UInt32] = (0..<Preferences.holdShortcut.count).compactMap { i in
            shortcuts[Preferences.indexToName("holdShortcut", i)]?.shortcut.carbonModifierFlags
        }
        let result = NativeHotkeyResolver.resolve(shortcuts: snapshots, holdShortcutModifiers: holdShortcutModifiers)
        setNativeCommandTabEnabled(false, Array(result.disable))
        setNativeCommandTabEnabled(true, Array(result.enable))
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

    /// Human-readable label for the action bound to `id`, resolved purely from the model — the id's
    /// shape plus `staticShortcutLabels` — NOT from `shortcutControls`. This is what lets the conflict
    /// dialog name a shortcut that isn't currently displayed in the recycled editor (which keeps only
    /// the on-screen shortcut in `shortcutControls`). Returns nil for ids with no known action.
    ///
    /// A numbered shortcut's hold and "and press" both belong to that shortcut's Trigger, so they
    /// resolve to e.g. "Shortcut 2 - Trigger" — naming WHICH shortcut, since "Select next window"
    /// alone doesn't disambiguate when several shortcuts exist.
    static func conflictLabel(_ id: String) -> String? {
        if arrowKeys.contains(id) { return NSLocalizedString("Arrow keys", comment: "") }
        if vimKeyActions.values.contains(id) { return NSLocalizedString("Vim keys", comment: "") }
        if id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut") {
            return shortcutTitle(Preferences.nameToIndex(id)) + " - " + ShortcutEditor.triggerLabel
        }
        return staticShortcutLabels[id]
    }

    /// Clear the shortcut bound to `id` and let the normal preference-change pipeline reconcile the
    /// registry and UI. Used by the conflict dialog's "Unassign existing shortcut and continue" for a
    /// shortcut that may not be on screen, so it goes through `Preferences` (cached UserDefaults)
    /// rather than mutating a live recorder. If that recorder happens to be displayed, sync it too.
    ///
    /// For a numbered shortcut's Trigger the hold can't stand alone, so "unassign" clears the "and
    /// press" (nextWindowShortcut) part — e.g. ⌥+Tab becomes ⌥+(unassigned) — whether the conflict
    /// was reported against the hold or the press.
    static func unassignShortcut(_ id: String) {
        let keyToClear = (id.hasPrefix("holdShortcut") || id.hasPrefix("nextWindowShortcut"))
            ? Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(id))
            : id
        Preferences.setShortcut(keyToClear, nil)
        shortcutControls[keyToClear]?.0.objectValue = nil
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

    // MARK: - Recorder lifecycle

    private static func initializeShortcutRecorderState(_ index: Int) {
        guard index < Preferences.shortcutCount else { return }
        let holdControlId = Preferences.indexToName("holdShortcut", index)
        let nextControlId = Preferences.indexToName("nextWindowShortcut", index)
        if let holdShortcut = shortcutControls[holdControlId]?.0 {
            holdShortcut.objectValue = Preferences.shortcut(holdControlId)
            shortcutChangedCallback(holdShortcut)
        }
        if let nextWindowShortcut = shortcutControls[nextControlId]?.0 {
            nextWindowShortcut.objectValue = Preferences.shortcut(nextControlId)
            shortcutChangedCallback(nextWindowShortcut)
        }
    }

    private static func refreshShortcutControlsDisplay() {
        shortcutControls.values.forEach {
            $0.0.needsDisplay = true
            $0.0.invalidateIntrinsicContentSize()
        }
    }
}
