import Cocoa
import ShortcutRecorder

/// A single recycled editor for the per-shortcut settings. Built once at ControlsTab init.
///
/// The user can configure N shortcuts (each its own modifier combo, filter rules, appearance
/// overrides, ordering rules). Previously the UI built one full editor view per shortcut and
/// toggled `isHidden` between them; that meant N × (~50 NSViews) resident at once, which made
/// every AppKit layout / key-state walk expensive — especially on macOS Tahoe where AppKit's
/// per-control work routes through SwiftUI internals.
///
/// The recycled design follows the same philosophy as `ExceptionEditorView` and the switcher's
/// `ThumbnailsView.recycledViews` pool: one editor exists, `bind(toShortcut:)` re-aims each of
/// its bound controls at a different preference key (and refreshes the displayed value). View
/// identity and tree shape stay constant across shortcut switches.
final class ShortcutEditor {
    let view: NSView

    private let trigger: TriggerBinding
    /// Panes are constructed lazily on first selection — only one is visible at a time, so
    /// building the other two upfront is pure cost (~30 controls each in the cascade walk).
    /// `bind(toShortcut:)` only re-binds panes that exist; the search index is populated with
    /// every pane's static `searchableStrings` at `init` time so cross-pane search still works
    /// before a pane is built.
    private var filteringPane: FilteringPane?
    private var appearancePane: AppearancePane?
    private var orderingPane: OrderingPane?
    private let tabControl: NSSegmentedControl
    private let outerContainer: NSStackView
    /// Flexible NSView pinned at the bottom of `outerContainer`. Absorbs the slack between the
    /// natural content height and `contentMinHeight` so the gap stays at the bottom (invisible)
    /// rather than between gravity areas (visible).
    private var bottomSpacer: NSView!
    private let editorWidth: CGFloat
    private(set) var currentIndex: Int = 0

    /// Currently selected tab segment (Filtering = 0, Appearance = 1, Ordering = 2). Shared
    /// across editor instances and persisted on the type so that re-opening Settings keeps the
    /// last-viewed segment.
    static var selectedTabSegment: Int = 0
    /// Minimum height for an editor's content block — anchored roughly to the Filtering pane
    /// (the tallest of the three tabs) so switching to a short tab like Ordering doesn't make
    /// the surrounding rounded section visibly snap up. The bottom just gets whitespace instead.
    private static let contentMinHeight: CGFloat = 400
    /// Fixed height for the Trigger row content (recorder + labels). Pinned rather than derived
    /// from `mainRow.fittingSize.height` because `RecorderControl`'s intrinsic height isn't
    /// guaranteed to be set when `TableGroupView.setMainRow` snapshots it, which previously
    /// produced inconsistent Trigger row heights across shortcuts.
    static let triggerRowContentHeight: CGFloat = 22

    /// Localized labels shared between the recycled shortcut editor and the fixed-bind gesture
    /// editor in `ControlsTab.makeGestureEditor`. Both build the same Trigger row + tab control
    /// shape, so exposing the strings here keeps a single source of truth for each one.
    static let triggerLabel = NSLocalizedString("Trigger", comment: "")
    static let tabLabelFiltering = NSLocalizedString("Filtering", comment: "")
    static let tabLabelAppearance = NSLocalizedString("Appearance", comment: "")
    static let tabLabelOrdering = NSLocalizedString("Ordering & Grouping", comment: "")

    init(width: CGFloat) {
        editorWidth = width
        trigger = TriggerBinding()

        // Populate the active SettingsSearchIndex with every pane's static strings — this is the
        // section-level search registration that lets queries match content in panes that haven't
        // been lazily built yet. The panes themselves register their highlight targets only once
        // they're constructed (so live highlights inside a built pane work as usual).
        SettingsSearchIndex.registerStrings(FilteringPane.searchableStrings)
        SettingsSearchIndex.registerStrings(AppearancePane.searchableStrings)
        SettingsSearchIndex.registerStrings(OrderingPane.searchableStrings)

        let triggerTable = TableGroupView(width: width)
        triggerTable.addRow(TableGroupView.Row(
            leftTitle: ShortcutEditor.triggerLabel,
            rightViews: [trigger.view]))

        let labels = [
            ShortcutEditor.tabLabelFiltering,
            ShortcutEditor.tabLabelAppearance,
            ShortcutEditor.tabLabelOrdering,
        ]
        tabControl = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
        tabControl.selectedSegment = ShortcutEditor.selectedTabSegment
        LabelAndControl.applySystemSelectedSegmentStyle(tabControl)
        tabControl.widthAnchor.constraint(equalToConstant: width).isActive = true
        let segmentWidth = width / CGFloat(labels.count)
        for i in 0..<labels.count { tabControl.setWidth(segmentWidth, forSegment: i) }

        // The view tree is: triggerTable / tabControl / one of the three lazily-built panes.
        // With `distribution = .gravityAreas` (NSStackView's default) plus the `contentMinHeight`
        // constraint, NSStackView distributes the slack between gravity areas in ways that don't
        // match the simple "pack at the top" mental model — leaving a gap between the trigger
        // row and the tab control + visible pane. Switching to `.fill` distribution + a trailing
        // flexible spacer puts the slack at the bottom, where it's invisible, regardless of how
        // many panes have been built.
        let bottomSpacer = NSView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        // The spacer must absorb slack ahead of any sibling. The triggerTable / tabControl /
        // pane views default to `.defaultLow` (250) hugging on the vertical axis, so we pin the
        // spacer well below that (1) — under `distribution = .fill`, NSStackView stretches the
        // lowest-hugging view first, which is what we want.
        bottomSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        bottomSpacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        self.bottomSpacer = bottomSpacer

        outerContainer = NSStackView()
        outerContainer.orientation = .vertical
        outerContainer.alignment = .leading
        outerContainer.spacing = TableGroupSetView.tableGroupSpacing
        outerContainer.distribution = .fill
        outerContainer.addArrangedSubview(triggerTable)
        outerContainer.addArrangedSubview(tabControl)
        outerContainer.addArrangedSubview(bottomSpacer)
        // Extra breathing room below the Trigger row — it's the headline action of the editor
        // and the tab control / content tables that follow are secondary configuration.
        outerContainer.setCustomSpacing(10, after: triggerTable)
        outerContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: ShortcutEditor.contentMinHeight).isActive = true
        view = outerContainer

        tabControl.onAction = { [weak self] control in
            self?.applySelectedSegment((control as! NSSegmentedControl).selectedSegment)
        }

        // Build the initially-selected pane so the editor isn't empty on first open. The other
        // two panes wait until the user clicks their tab segment.
        ensurePaneBuilt(forSegment: ShortcutEditor.selectedTabSegment)
    }

    /// Re-aim every owned binding at `index`'s preference keys, then refresh visible state. Only
    /// already-constructed panes are rebound; unbuilt panes pick up the current index from
    /// `ensurePaneBuilt` when they're eventually created.
    func bind(toShortcut index: Int) {
        currentIndex = index
        trigger.bind(toShortcut: index)
        filteringPane?.bind(toShortcut: index)
        appearancePane?.bind(toShortcut: index)
        orderingPane?.bind(toShortcut: index)
    }

    /// Re-display values without changing the bound index. Called when a global appearance pref
    /// changes (non-overridden controls need to resnap to the new global) or after a pro-lock
    /// transition (stored values may have been downgraded).
    func refreshFromCurrentBind() {
        bind(toShortcut: currentIndex)
    }

    /// Programmatically switch to the Appearance segment. Used by AppearanceTab's "Overridden in
    /// Shortcut: N" link to deep-link into the right tab.
    func showAppearanceSegment() {
        applySelectedSegment(1)
    }

    /// Externally-driven tab swap — used by ControlsTab to keep the gesture editor's tab in sync
    /// with the shortcut editor when the user changes it on the other one.
    func applySelectedSegment(_ segment: Int) {
        ShortcutEditor.selectedTabSegment = segment
        tabControl.selectedSegment = segment
        ensurePaneBuilt(forSegment: segment)
    }

    private func ensurePaneBuilt(forSegment segment: Int) {
        switch segment {
        case 0:
            if filteringPane == nil {
                let pane = FilteringPane(width: editorWidth)
                pane.bind(toShortcut: currentIndex)
                insertPaneBeforeBottomSpacer(pane.view)
                filteringPane = pane
            }
        case 1:
            if appearancePane == nil {
                let pane = AppearancePane(width: editorWidth)
                pane.bind(toShortcut: currentIndex)
                insertPaneBeforeBottomSpacer(pane.view)
                appearancePane = pane
            }
        case 2:
            if orderingPane == nil {
                let pane = OrderingPane(width: editorWidth)
                pane.bind(toShortcut: currentIndex)
                insertPaneBeforeBottomSpacer(pane.view)
                orderingPane = pane
            }
        default: break
        }
        filteringPane?.view.isHidden = segment != 0
        appearancePane?.view.isHidden = segment != 1
        orderingPane?.view.isHidden = segment != 2
    }

    /// Insert a freshly-built pane just before the trailing `bottomSpacer`, so the spacer
    /// remains at the bottom and continues to absorb the `contentMinHeight` slack.
    private func insertPaneBeforeBottomSpacer(_ paneView: NSView) {
        let spacerIndex = outerContainer.arrangedSubviews.firstIndex(of: bottomSpacer) ?? outerContainer.arrangedSubviews.count
        outerContainer.insertArrangedSubview(paneView, at: spacerIndex)
    }

    /// Per-segment static searchable strings for the tab control. Consumed by
    /// `SettingsWindow.highlightTarget(_ segmentedControl:)` so a query that matches content
    /// inside a (possibly unbuilt) pane lights up the corresponding tab segment.
    var tabSegmentSearchableStringsEntry: (key: ObjectIdentifier, perSegmentStrings: [[String]]) {
        (ObjectIdentifier(tabControl), [
            FilteringPane.searchableStrings,
            AppearancePane.searchableStrings,
            OrderingPane.searchableStrings,
        ])
    }
}

// MARK: - Trigger row (hold + next-window recorders)

/// The Trigger row owns two recorders (hold + next-window). They have a cross-reference: the
/// next-window recorder is restricted to the modifiers of the hold key. On rebind we swap both
/// recorders' identifiers, refresh both displayed values, and resync `shortcutControls` so other
/// modules (CustomRecorderControl, the conflict detector) find the right control.
final class TriggerBinding {
    let view: NSView
    private let holdRecorder: CustomRecorderControl
    private let nextRecorder: CustomRecorderControl
    private let holdLabel = NSTextField(labelWithString: "")
    private let andPressLabel: NSTextField
    private static let holdLabelText = NSLocalizedString("Hold", comment: "")
    private static let andPressText = NSLocalizedString("and press", comment: "")
    // The next-window recorder's human-readable name, stored alongside it in `shortcutControls`.
    private static let selectNextText = NSLocalizedString("Select next window", comment: "")
    private var currentIndex: Int = -1

    init() {
        // Placeholder identifier — replaced in bind().
        holdRecorder = CustomRecorderControl(nil, false, "holdShortcut0")
        nextRecorder = CustomRecorderControl(nil, true, "nextWindowShortcut0")

        let holdLabelField = LabelAndControl.makeLabel(TriggerBinding.holdLabelText)
        andPressLabel = LabelAndControl.makeLabel(TriggerBinding.andPressText)

        let stack = NSStackView(views: [holdLabelField, holdRecorder, andPressLabel, nextRecorder])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = TableGroupView.spacing
        stack.heightAnchor.constraint(equalToConstant: ShortcutEditor.triggerRowContentHeight).isActive = true
        view = stack

        // Recorder edits need three things to happen in order:
        // 1. Persist the new shortcut into `Preferences` (via `controlWasChanged`). Otherwise
        //    the value lives only in `RecorderControl.objectValue` and rebinding to a different
        //    shortcut later loses it — the sidebar row's summary and the recorder's displayed
        //    value both come from `Preferences.shortcut`, so they'd show stale state.
        // 2. Re-run `shortcutChangedCallback` so the global hotkey gets (re-)registered with
        //    the new value and modifier restrictions cascade to the sibling recorder.
        // 3. Refresh the sidebar row's summary so the user sees the new modifier + key combo
        //    next to "Shortcut N" without needing to switch rows and come back.
        holdRecorder.onAction = { [weak self] _ in
            guard let self else { return }
            LabelAndControl.controlWasChanged(self.holdRecorder, nil)
            ControlsTab.shortcutChangedCallback(self.holdRecorder)
            ControlsTab.refreshShortcutRowContent(forIndex: self.currentIndex)
        }
        nextRecorder.onAction = { [weak self] _ in
            guard let self else { return }
            LabelAndControl.controlWasChanged(self.nextRecorder, nil)
            ControlsTab.shortcutChangedCallback(self.nextRecorder)
            ControlsTab.refreshShortcutRowContent(forIndex: self.currentIndex)
        }
    }

    func bind(toShortcut index: Int) {
        // Clear any previous mapping in `shortcutControls`.
        if currentIndex >= 0 {
            ControlsTab.shortcutControls.removeValue(forKey: Preferences.indexToName("holdShortcut", currentIndex))
            ControlsTab.shortcutControls.removeValue(forKey: Preferences.indexToName("nextWindowShortcut", currentIndex))
        }
        currentIndex = index
        let holdKey = Preferences.indexToName("holdShortcut", index)
        let nextKey = Preferences.indexToName("nextWindowShortcut", index)
        holdRecorder.identifier = NSUserInterfaceItemIdentifier(holdKey)
        nextRecorder.identifier = NSUserInterfaceItemIdentifier(nextKey)
        holdRecorder.objectValue = Preferences.shortcut(holdKey)
        nextRecorder.objectValue = Preferences.shortcut(nextKey)
        ControlsTab.shortcutControls[holdKey] = (holdRecorder, TriggerBinding.holdLabelText)
        ControlsTab.shortcutControls[nextKey] = (nextRecorder, TriggerBinding.selectNextText)
        // Reapply modifier restriction on the next-window recorder based on the hold shortcut.
        if let holdModifiers = Preferences.shortcut(holdKey)?.modifierFlags {
            nextRecorder.restrictModifiers(holdModifiers)
        } else {
            nextRecorder.restrictModifiers([])
        }
    }
}

// MARK: - Filtering pane

/// Filtering tab content: per-shortcut filtering dropdowns. All controls bound via
/// ShortcutBoundDropdown; no override semantics here.
final class FilteringPane {
    // Single source of truth for the pane's labels — referenced by both `init` (when the pane is
    // actually built) and `searchableStrings` (used by the parent ShortcutEditor at section-build
    // time to populate the search index even before the pane has been built lazily).
    private static let labelApps = NSLocalizedString("Show windows from applications", comment: "")
    private static let labelSpaces = NSLocalizedString("Show windows from Spaces", comment: "")
    private static let labelScreens = NSLocalizedString("Show windows from screens", comment: "")
    private static let labelMinimized = NSLocalizedString("Show minimized windows", comment: "")
    private static let labelHidden = NSLocalizedString("Show hidden windows", comment: "")
    private static let labelFullscreen = NSLocalizedString("Show fullscreen windows", comment: "")
    private static let labelWindowless = NSLocalizedString("Show apps with no open window", comment: "")

    /// All text contributed to the search index by this pane. Includes row titles + the localized
    /// strings of each dropdown's `MacroPreference` cases. `ShortcutEditor.init` registers this
    /// list into the active `SettingsSearchIndex` so search matches inside the pane work even
    /// before the pane is constructed (the user-facing button to switch to this tab still lights
    /// up; clicking it triggers the lazy build, after which in-pane highlights work normally).
    static let searchableStrings: [String] = [
        labelApps, labelSpaces, labelScreens,
        labelMinimized, labelHidden, labelFullscreen, labelWindowless,
    ] + AppsToShowPreference.allCases.map { $0.localizedString }
      + SpacesToShowPreference.allCases.map { $0.localizedString }
      + ScreensToShowPreference.allCases.map { $0.localizedString }
      + ShowHowPreference.allCases.map { $0.localizedString }

    let view: NSView
    private let appsToShow: ShortcutBoundDropdown
    private let spacesToShow: ShortcutBoundDropdown
    private let screensToShow: ShortcutBoundDropdown
    private let showMinimized: ShortcutBoundDropdown
    private let showHidden: ShortcutBoundDropdown
    private let showFullscreen: ShortcutBoundDropdown
    private let showWindowless: ShortcutBoundDropdown

    init(width: CGFloat) {
        appsToShow = ShortcutBoundDropdown(baseName: "appsToShow", cases: AppsToShowPreference.allCases)
        spacesToShow = ShortcutBoundDropdown(baseName: "spacesToShow", cases: SpacesToShowPreference.allCases)
        screensToShow = ShortcutBoundDropdown(baseName: "screensToShow", cases: ScreensToShowPreference.allCases)
        showMinimized = ShortcutBoundDropdown(baseName: "showMinimizedWindows", cases: ShowHowPreference.allCases)
        showHidden = ShortcutBoundDropdown(baseName: "showHiddenWindows", cases: ShowHowPreference.allCases)
        showFullscreen = ShortcutBoundDropdown(baseName: "showFullscreenWindows", cases: ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
        showWindowless = ShortcutBoundDropdown(baseName: "showWindowlessApps", cases: ShowHowPreference.allCases)

        let table = TableGroupView(width: width)
        table.addRow(leftViews: [TableGroupView.makeText(Self.labelApps)], rightViews: [appsToShow])
        table.addRow(leftViews: [TableGroupView.makeText(Self.labelSpaces)], rightViews: [spacesToShow])
        table.addRow(leftViews: [TableGroupView.makeText(Self.labelScreens)], rightViews: [screensToShow])
        table.addRow(TableGroupView.Row(leftTitle: Self.labelMinimized, rightViews: [showMinimized]))
        table.addRow(TableGroupView.Row(leftTitle: Self.labelHidden, rightViews: [showHidden]))
        table.addRow(TableGroupView.Row(leftTitle: Self.labelFullscreen, rightViews: [showFullscreen]))
        table.addRow(TableGroupView.Row(leftTitle: Self.labelWindowless, rightViews: [showWindowless]))
        view = table
    }

    func bind(toShortcut index: Int) {
        appsToShow.bind(toShortcut: index)
        spacesToShow.bind(toShortcut: index)
        screensToShow.bind(toShortcut: index)
        showMinimized.bind(toShortcut: index)
        showHidden.bind(toShortcut: index)
        showFullscreen.bind(toShortcut: index)
        showWindowless.bind(toShortcut: index)
    }
}

// MARK: - Ordering & Grouping pane

final class OrderingPane {
    private static let labelGroupApps = NSLocalizedString("Group apps", comment: "")
    private static let labelGroupTabs = NSLocalizedString("Group tabs", comment: "")
    private static let labelWindowOrder = NSLocalizedString("Order windows by", comment: "")

    /// See `FilteringPane.searchableStrings`.
    static let searchableStrings: [String] = [
        labelGroupApps, labelGroupTabs, labelWindowOrder,
    ] + GroupAppsPreference.allCases.map { $0.localizedString }
      + GroupTabsPreference.allCases.map { $0.localizedString }
      + WindowOrderPreference.allCases.map { $0.localizedString }

    let view: NSView
    private let showAppsOrWindows: ShortcutBoundDropdown
    private let showTabsAsWindows: ShortcutBoundDropdown
    private let windowOrder: ShortcutBoundDropdown

    init(width: CGFloat) {
        showAppsOrWindows = ShortcutBoundDropdown(baseName: "showAppsOrWindows", cases: GroupAppsPreference.allCases)
        showTabsAsWindows = ShortcutBoundDropdown(baseName: "showTabsAsWindows", cases: GroupTabsPreference.allCases)
        windowOrder = ShortcutBoundDropdown(baseName: "windowOrder", cases: WindowOrderPreference.allCases)

        let table = TableGroupView(width: width)
        table.addRow(TableGroupView.Row(leftTitle: Self.labelGroupApps, rightViews: [showAppsOrWindows]))
        table.addRow(TableGroupView.Row(leftTitle: Self.labelGroupTabs, rightViews: [showTabsAsWindows]))
        table.addRow(TableGroupView.Row(leftTitle: Self.labelWindowOrder, rightViews: [windowOrder]))
        view = table
    }

    func bind(toShortcut index: Int) {
        showAppsOrWindows.bind(toShortcut: index)
        showTabsAsWindows.bind(toShortcut: index)
        windowOrder.bind(toShortcut: index)
    }
}

// MARK: - Appearance pane (override controls)

final class AppearancePane {
    /// See `FilteringPane.searchableStrings`. The labels (Size / Theme / After keys released /
    /// Preview selected window) are shared with the global appearance UI; reference the same
    /// constants from `AppearanceTab` rather than re-declaring them.
    static let searchableStrings: [String] = [
        AppearanceTab.labelSize,
        AppearanceTab.labelTheme,
        AppearanceTab.labelShortcutStyle,
        AppearanceTab.labelPreviewSelectedWindow,
        ProBadgeView.proLabel,
    ] + AppearanceStylePreference.allCases.map { $0.localizedString }
      + AppearanceSizePreference.allCases.map { $0.localizedString }
      + AppearanceThemePreference.allCases.map { $0.localizedString }
      + ShortcutStylePreference.allCases.map { $0.localizedString }

    let view: NSView
    private let style: ShortcutOverrideRadios
    private let size: ShortcutOverrideSegmented
    private let theme: ShortcutOverrideSegmented
    private let shortcutStyle: ShortcutOverrideSegmented
    private let preview: ShortcutOverrideSwitch

    init(width: CGFloat) {
        let onChange: () -> Void = {
            AppearanceTab.refreshAllOverrideInfoLabels()
        }

        style = ShortcutOverrideRadios(
            baseName: "appearanceStyleOverride",
            cases: AppearanceStylePreference.allCases,
            globalIndex: { Preferences.appearanceStyle.index },
            proGatedIndices: AppearanceTab.proGatedAppearanceStyleIndices(),
            onChange: onChange)
        AppearanceTab.addProBadgesToStyleButtons(style.stack)

        size = ShortcutOverrideSegmented(
            baseName: "appearanceSizeOverride",
            cases: AppearanceSizePreference.allCases,
            globalIndex: { Preferences.appearanceSize.index },
            proGatedIndices: [AppearanceSizePreference.allCases.firstIndex(of: .auto)!],
            segmentWidth: 100,
            attachBadge: { c in AppearanceTab.addProBadgeToAutoSegment(c) },
            refreshBadge: { c, overlay in
                AppearanceTab.refreshTrailingSegmentBadge(c, proIndex: AppearanceSizePreference.allCases.firstIndex(of: .auto)!, overlay: overlay)
            },
            onChange: onChange)

        theme = ShortcutOverrideSegmented(
            baseName: "appearanceThemeOverride",
            cases: AppearanceThemePreference.allCases,
            globalIndex: { Preferences.appearanceTheme.index },
            proGatedIndices: [],
            segmentWidth: 100,
            attachBadge: nil,
            refreshBadge: nil,
            onChange: onChange)

        shortcutStyle = ShortcutOverrideSegmented(
            baseName: "shortcutStyleOverride",
            cases: ShortcutStylePreference.allCases,
            globalIndex: { Preferences.shortcutStyle.index },
            proGatedIndices: [ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!],
            segmentWidth: 100,
            attachBadge: { c in AppearanceTab.addProBadgeToShortcutStyleSegment(c, proIndex: ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!) },
            refreshBadge: { c, overlay in
                AppearanceTab.refreshTrailingSegmentBadge(c, proIndex: ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!, overlay: overlay)
            },
            onChange: onChange)

        preview = ShortcutOverrideSwitch(
            baseName: "previewFocusedWindowOverride",
            globalValue: { Preferences.previewSelectedWindow },
            onChange: onChange)

        let table = TableGroupView(width: width)
        let styleRow = NSStackView(views: [style.stack, style.unlink])
        styleRow.orientation = .horizontal
        styleRow.alignment = .centerY
        styleRow.spacing = TableGroupView.padding
        table.addRow(secondaryViews: [styleRow], secondaryViewsAlignment: .centerX)
        table.addRow(leftText: AppearanceTab.labelSize, rightViews: [size.segmented, size.unlink])
        table.addRow(leftText: AppearanceTab.labelTheme, rightViews: [theme.segmented, theme.unlink])
        table.addRow(leftText: AppearanceTab.labelShortcutStyle, rightViews: [shortcutStyle.segmented, shortcutStyle.unlink])
        table.addRow(leftText: AppearanceTab.labelPreviewSelectedWindow, rightViews: [preview.toggle, preview.unlink])
        view = table
    }

    func bind(toShortcut index: Int) {
        style.bind(toShortcut: index)
        size.bind(toShortcut: index)
        theme.bind(toShortcut: index)
        shortcutStyle.bind(toShortcut: index)
        preview.bind(toShortcut: index)
    }
}

// MARK: - Bindings: simple per-shortcut

/// A dropdown bound to a per-shortcut preference key (e.g. `appsToShow2`). On `bind`, swaps the
/// identifier and refreshes the selected item from UserDefaults. Writes go through the inherited
/// `onAction` → `LabelAndControl.controlWasChanged`, which reads the current identifier — so
/// `bind` is the only place we need to keep the binding consistent.
final class ShortcutBoundDropdown: PopupButtonLikeSystemSettings {
    private let baseName: String
    private let cases: [MacroPreference]

    init(baseName: String, cases: [MacroPreference]) {
        self.baseName = baseName
        self.cases = cases
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: cases.map { $0.localizedString })
        // Identifier set in bind(); placeholder until then.
        identifier = NSUserInterfaceItemIdentifier(Preferences.indexToName(baseName, 0))
        onAction = { control in
            LabelAndControl.controlWasChanged(control, nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }

    func bind(toShortcut index: Int) {
        let key = Preferences.indexToName(baseName, index)
        identifier = NSUserInterfaceItemIdentifier(key)
        let selectedIndex = CachedUserDefaults.intFromMacroPref(key, cases)
        let clamped = max(0, min(selectedIndex, numberOfItems - 1))
        selectItem(at: clamped)
    }
}

// MARK: - Bindings: override controls

/// A segmented control wired to a per-shortcut "override" preference (e.g. `appearanceSizeOverride2`).
/// Displays the override value when one is set, otherwise the global. Owns its own unlink button
/// and an optional pro-badge overlay on a Pro-gated segment.
final class ShortcutOverrideSegmented {
    let segmented: NSSegmentedControl
    let unlink: NSButton
    private let badgeOverlay: ProBadgeView.SegmentOverlay?

    private let baseName: String
    private let cases: [MacroPreference]
    private let globalIndex: () -> Int
    private let proGatedIndices: Set<Int>
    private let refreshBadge: ((NSSegmentedControl, ProBadgeView.SegmentOverlay) -> Void)?
    private let onChange: (() -> Void)?
    private var currentShortcutIndex: Int = 0

    init(baseName: String,
         cases: [MacroPreference],
         globalIndex: @escaping () -> Int,
         proGatedIndices: Set<Int>,
         segmentWidth: CGFloat,
         attachBadge: ((NSSegmentedControl) -> ProBadgeView.SegmentOverlay)?,
         refreshBadge: ((NSSegmentedControl, ProBadgeView.SegmentOverlay) -> Void)?,
         onChange: (() -> Void)?) {
        self.baseName = baseName
        self.cases = cases
        self.globalIndex = globalIndex
        self.proGatedIndices = proGatedIndices
        self.refreshBadge = refreshBadge
        self.onChange = onChange

        segmented = LabelAndControl.makeSegmentedControl(
            Preferences.indexToName(baseName, 0), cases, segmentWidth: segmentWidth, extraAction: nil)
        badgeOverlay = attachBadge?(segmented)
        if let overlay = badgeOverlay {
            overlay.badge.onWindowKeyChanged = { [weak segmented] in
                guard let segmented, let refreshBadge else { return }
                refreshBadge(segmented, overlay)
            }
        }
        unlink = ShortcutEditor.makeUnlinkButton()

        let weakSelf = WeakRef(self)
        segmented.onAction = { control in
            weakSelf.value?.handleClick(control as! NSSegmentedControl)
        }
        unlink.onAction = { _ in
            weakSelf.value?.unlinkOverride()
        }
    }

    func bind(toShortcut index: Int) {
        currentShortcutIndex = index
        let key = Preferences.indexToName(baseName, index)
        segmented.identifier = NSUserInterfaceItemIdentifier(key)
        let displayedIndex: Int
        if Preferences.hasOverride(baseName, index) {
            displayedIndex = CachedUserDefaults.intFromMacroPref(key, cases)
        } else {
            displayedIndex = globalIndex()
        }
        let clamped = max(0, min(displayedIndex, cases.count - 1))
        segmented.selectedSegment = clamped
        unlink.isHidden = !Preferences.hasOverride(baseName, index)
        refreshOverlayIfNeeded()
    }

    private func handleClick(_ control: NSSegmentedControl) {
        let newIndex = control.selectedSegment
        // Pro-lock intercept: clicking a Pro-gated segment while locked redirects to Upgrade.
        if proGatedIndices.contains(newIndex) && LicenseManager.shared.isProLocked {
            let stored = CachedUserDefaults.intFromMacroPref(
                Preferences.indexToName(baseName, currentShortcutIndex), cases)
            let revertTo = Preferences.hasOverride(baseName, currentShortcutIndex) ? stored : globalIndex()
            control.selectedSegment = max(0, min(revertTo, cases.count - 1))
            refreshOverlayIfNeeded()
            UpgradeTab.navigateToUpgradeTab()
            return
        }
        let key = Preferences.indexToName(baseName, currentShortcutIndex)
        let decision = OverrideClickResolver.decide(
            newIndex: newIndex,
            hasOverride: Preferences.hasOverride(baseName, currentShortcutIndex),
            storedOverrideValue: UserDefaults.standard.string(forKey: key),
            globalIndex: globalIndex(),
            valueAtIndex: { String($0) })
        if case .write(let value) = decision {
            Preferences.set(key, value)
            unlink.isHidden = false
            onChange?()
        }
        refreshOverlayIfNeeded()
    }

    private func unlinkOverride() {
        Preferences.removeOverride(baseName, currentShortcutIndex)
        // Resnap to global.
        segmented.selectedSegment = max(0, min(globalIndex(), cases.count - 1))
        unlink.isHidden = true
        refreshOverlayIfNeeded()
        onChange?()
    }

    private func refreshOverlayIfNeeded() {
        if let overlay = badgeOverlay, let refreshBadge {
            refreshBadge(segmented, overlay)
        }
    }
}

/// Radio-button equivalent (an NSStackView of `ImageTextButtonView`s) bound to a per-shortcut
/// override preference. Used for the Appearance Style picker.
final class ShortcutOverrideRadios {
    let stack: NSStackView
    let unlink: NSButton

    private let baseName: String
    private let cases: [MacroPreference]
    private let globalIndex: () -> Int
    private let proGatedIndices: Set<Int>
    private let onChange: (() -> Void)?
    private var currentShortcutIndex: Int = 0

    init(baseName: String,
         cases: [MacroPreference],
         globalIndex: @escaping () -> Int,
         proGatedIndices: Set<Int>,
         onChange: (() -> Void)?) {
        self.baseName = baseName
        self.cases = cases
        self.globalIndex = globalIndex
        self.proGatedIndices = proGatedIndices
        self.onChange = onChange

        stack = LabelAndControl.makeImageRadioButtons(
            Preferences.indexToName(baseName, 0),
            cases as! [ImageMacroPreference],
            extraAction: nil,
            buttonSpacing: 10,
            proGatedIndices: proGatedIndices)
        unlink = ShortcutEditor.makeUnlinkButton()

        let weakSelf = WeakRef(self)
        let buttonViews = stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
        for (i, buttonView) in buttonViews.enumerated() {
            buttonView.onClick = { [weak stack] _ in
                guard let _ = stack else { return }
                weakSelf.value?.handleClick(buttonIndex: i)
            }
        }
        unlink.onAction = { _ in
            weakSelf.value?.unlinkOverride()
        }
    }

    func bind(toShortcut index: Int) {
        currentShortcutIndex = index
        let key = Preferences.indexToName(baseName, index)
        // Radios don't use NSControl.identifier for their writes — they call controlWasChanged
        // with a manually computed value. So no identifier-swap needed; we re-target manually below.
        let displayedIndex: Int
        if Preferences.hasOverride(baseName, index) {
            displayedIndex = CachedUserDefaults.intFromMacroPref(key, cases)
        } else {
            displayedIndex = globalIndex()
        }
        let buttonViews = stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
        for (i, b) in buttonViews.enumerated() {
            b.state = (i == displayedIndex) ? .on : .off
        }
        unlink.isHidden = !Preferences.hasOverride(baseName, index)
    }

    private func handleClick(buttonIndex i: Int) {
        let buttonViews = stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
        let key = Preferences.indexToName(baseName, currentShortcutIndex)
        if proGatedIndices.contains(i) && LicenseManager.shared.isProLocked {
            // Snap back to the stored value.
            let storedIndex = Int(UserDefaults.standard.string(forKey: key) ?? "") ?? -1
            for (j, b) in buttonViews.enumerated() { b.state = (j == storedIndex) ? .on : .off }
            UpgradeTab.navigateToUpgradeTab()
            return
        }
        let decision = OverrideClickResolver.decide(
            newIndex: i,
            hasOverride: Preferences.hasOverride(baseName, currentShortcutIndex),
            storedOverrideValue: UserDefaults.standard.string(forKey: key),
            globalIndex: globalIndex(),
            valueAtIndex: { String($0) })
        let onIndex: Int
        switch decision {
        case .skip:
            onIndex = Preferences.hasOverride(baseName, currentShortcutIndex)
                ? (Int(UserDefaults.standard.string(forKey: key) ?? "") ?? -1)
                : globalIndex()
        case .write(let value):
            Preferences.set(key, value)
            onIndex = i
        }
        for (j, b) in buttonViews.enumerated() { b.state = (j == onIndex) ? .on : .off }
        if case .write = decision {
            unlink.isHidden = false
            onChange?()
        }
    }

    private func unlinkOverride() {
        Preferences.removeOverride(baseName, currentShortcutIndex)
        let buttonViews = stack.arrangedSubviews.compactMap { $0 as? ImageTextButtonView }
        let gi = globalIndex()
        for (j, b) in buttonViews.enumerated() { b.state = (j == gi) ? .on : .off }
        unlink.isHidden = true
        onChange?()
    }
}

/// Switch bound to a per-shortcut override preference. Used for "Preview selected window".
final class ShortcutOverrideSwitch {
    let toggle: Switch
    let unlink: NSButton

    private let baseName: String
    private let globalValue: () -> Bool
    private let onChange: (() -> Void)?
    private var currentShortcutIndex: Int = 0

    init(baseName: String, globalValue: @escaping () -> Bool, onChange: (() -> Void)?) {
        self.baseName = baseName
        self.globalValue = globalValue
        self.onChange = onChange
        toggle = LabelAndControl.makeSwitch(Preferences.indexToName(baseName, 0), extraAction: nil)
        unlink = ShortcutEditor.makeUnlinkButton()

        let weakSelf = WeakRef(self)
        toggle.onAction = { c in
            weakSelf.value?.handleToggle(c as! Switch)
        }
        unlink.onAction = { _ in
            weakSelf.value?.unlinkOverride()
        }
    }

    func bind(toShortcut index: Int) {
        currentShortcutIndex = index
        let key = Preferences.indexToName(baseName, index)
        toggle.identifier = NSUserInterfaceItemIdentifier(key)
        let on: Bool
        if Preferences.hasOverride(baseName, index) {
            on = CachedUserDefaults.bool(key)
        } else {
            on = globalValue()
        }
        toggle.setSilently(on ? .on : .off)
        unlink.isHidden = !Preferences.hasOverride(baseName, index)
    }

    private func handleToggle(_ control: Switch) {
        // Toggling always changes state — always write the override.
        let key = Preferences.indexToName(baseName, currentShortcutIndex)
        Preferences.set(key, control.state == .on ? "true" : "false")
        unlink.isHidden = false
        onChange?()
    }

    private func unlinkOverride() {
        Preferences.removeOverride(baseName, currentShortcutIndex)
        toggle.setSilently(globalValue() ? .on : .off)
        unlink.isHidden = true
        onChange?()
    }
}

// MARK: - Shared helpers

extension ShortcutEditor {
    /// Builds an unlink button used by all override bindings. Visibility is managed by each
    /// binding's `bind()` based on `Preferences.hasOverride`.
    static func makeUnlinkButton() -> NSButton {
        let image = NSImage.fromSymbol(.link, pointSize: 14)
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        if #available(macOS 10.14, *) {
            button.contentTintColor = .controlAccentColor
        }
        button.toolTip = NSLocalizedString("Sync with global value", comment: "")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.isHidden = true
        return button
    }
}

/// Tiny weak-reference helper so closures can capture `self` without holding a strong cycle.
private final class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
