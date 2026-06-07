import Cocoa

private struct SettingsSectionDefinition {
    let id: String
    let title: String
    let symbol: Symbols
    /// Deferred view builder so `addSection` can wrap construction in
    /// `SettingsSearchIndex.indexed { ... }` and harvest inline-registered search strings +
    /// highlight targets as the section's factories build their widgets. The closure is invoked
    /// exactly once, in `addSection`.
    let builder: () -> NSView
    /// Optional hook for sections whose searchable content includes sidebar rows that are rebuilt
    /// *after* the initial build (ControlsTab's shortcut rows). When set, `addSection` skips
    /// `SidebarListRow`s in the build-time walk — they'd otherwise be captured as base targets that
    /// go stale on the next rebuild — and this closure re-registers the current rows into the
    /// section's *dynamic* search content (at build time, and again after each rebuild via
    /// `refreshSectionSearchContent`). nil for sections with no such rows.
    let registerDynamicSearchContent: (() -> Void)?
}

private final class SettingsSection {
    let id: String
    let title: String
    let icon: NSImage
    let container: NSView
    let anchor: NSView
    let search: SettingsSectionSearchContent
    /// See `SettingsSectionDefinition.registerDynamicSearchContent`. Re-run inside a fresh indexed
    /// scope by `refreshSectionSearchContent` to refresh this section's dynamic search content.
    let registerDynamicSearchContent: (() -> Void)?
    let interSectionSpacingConstraint: NSLayoutConstraint
    let bottomSpacingConstraint: NSLayoutConstraint
    let titleTopConstraint: NSLayoutConstraint

    init(_ id: String,
         _ title: String,
         _ icon: NSImage,
         _ container: NSView,
         _ anchor: NSView,
         _ search: SettingsSectionSearchContent,
         _ registerDynamicSearchContent: (() -> Void)?,
         _ interSectionSpacingConstraint: NSLayoutConstraint,
         _ bottomSpacingConstraint: NSLayoutConstraint,
         _ titleTopConstraint: NSLayoutConstraint) {
        self.id = id
        self.title = title
        self.icon = icon
        self.container = container
        self.anchor = anchor
        self.search = search
        self.registerDynamicSearchContent = registerDynamicSearchContent
        self.interSectionSpacingConstraint = interSectionSpacingConstraint
        self.bottomSpacingConstraint = bottomSpacingConstraint
        self.titleTopConstraint = titleTopConstraint
    }

    func setDynamicSearchContent(_ strings: [String], _ targets: [SettingsSearchHighlightTarget]) {
        search.setDynamic(strings: strings, targets: targets)
    }

    func matches(_ query: String) -> Bool {
        search.matches(query)
    }

    func highlightMatches(_ query: String) {
        search.highlightMatches(query)
    }

    func clearHighlights() {
        search.clearHighlights()
    }
}

private final class SettingsSidebarCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier(rawValue: "SettingsSidebarCell")
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { refreshStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupView() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(titleLabel)
        // Standard `NSTableCellView` layout for an `NSTableView.style = .sourceList` sidebar:
        // a small leading inset, an icon, a fixed gap, then the title label. AppKit handles the
        // selection highlight pill and the sidebar material/background.
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsWindow.sidebarItemContentInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -SettingsWindow.sidebarItemContentInset),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshStyle()
    }

    func configure(_ section: SettingsSection) {
        titleLabel.stringValue = section.title
        iconView.image = section.icon
        iconView.image?.isTemplate = true
        refreshStyle()
    }

    private func refreshStyle() {
        let selected = backgroundStyle == .emphasized
        titleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.textColor = selected ? .white : .labelColor
        if #available(macOS 10.14, *) {
            iconView.contentTintColor = selected ? .white : .secondaryLabelColor
        }
    }
}

final class UpgradeButton: ProGradientButton {
    private var heightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        heightConstraint = heightAnchor.constraint(equalToConstant: 24)
        heightConstraint.isActive = true
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func layout() {
        super.layout()
        refreshEmailTooltip()
    }

    func refreshTitle() {
        let result = NSMutableAttributedString()
        let mainAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        ]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        ]
        let state = LicenseManager.shared.state
        if case .pro = state {
            let title = LicenseManager.shared.isLifetimeVariant
                ? NSLocalizedString("Pro Lifetime activated", comment: "")
                : NSLocalizedString("Pro activated", comment: "")
            if let email = LicenseManager.shared.customerEmail {
                result.append(NSAttributedString(string: title, attributes: secondaryAttrs))
                result.append(NSAttributedString(string: "\n", attributes: secondaryAttrs))
                result.append(NSAttributedString(string: email, attributes: mainAttrs))
            } else {
                result.append(NSAttributedString(string: title, attributes: mainAttrs))
            }
        } else {
            let subtitleText: String
            if case .trial(let daysRemaining) = state {
                subtitleText = String(format: NSLocalizedString("Trial: %d days remaining", comment: ""), daysRemaining)
            } else if case .proExpired = state {
                subtitleText = NSLocalizedString("License doesn't cover this version", comment: "")
            } else {
                subtitleText = NSLocalizedString("Trial expired", comment: "")
            }
            result.append(NSAttributedString(string: subtitleText, attributes: secondaryAttrs))
            result.append(NSAttributedString(string: "\n", attributes: secondaryAttrs))
            result.append(NSAttributedString(string: NSLocalizedString("Get Pro", comment: ""), attributes: mainAttrs))
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        attributedTitle = result
        if #available(macOS 10.14, *) {
            contentTintColor = .white
        }
        let hasSecondLine: Bool
        if case .pro = state, LicenseManager.shared.customerEmail == nil {
            hasSecondLine = false
        } else {
            hasSecondLine = true
        }
        heightConstraint.constant = hasSecondLine ? 35 : 24
        refreshEmailTooltip()
    }

    private func refreshEmailTooltip() {
        guard case .pro = LicenseManager.shared.state,
              let email = LicenseManager.shared.customerEmail else {
            toolTip = nil
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        let emailWidth = (email as NSString).size(withAttributes: attrs).width
        toolTip = emailWidth > bounds.width ? email : nil
    }
}

private final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class SidebarTableView: NSTableView {
    weak var tabPeer: NSView?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    // Pin Tab navigation to a closed search ↔ sidebar loop. nextKeyView assignments alone
    // weren't enough — AppKit's auto-walker was still discovering inner sub-views of the
    // search field, the scroll view, and the split view. Overriding the *valid* variants
    // short-circuits the walker because that's the method AppKit calls during dispatch.
    override var nextValidKeyView: NSView? { tabPeer }
    override var previousValidKeyView: NSView? { tabPeer }
}

private final class SidebarSearchField: NSSearchField {
    weak var tabPeer: NSView?

    override var nextValidKeyView: NSView? { tabPeer }
    override var previousValidKeyView: NSView? { tabPeer }
}

class SettingsWindow: NSWindow {
    static let contentWidth = CGFloat(710)
    static let width = contentWidth
    /// Horizontal margin inside each section between the section's container and the
    /// TableGroupView's rounded background, so the gray-bg blocks "float" inside the section
    /// rather than extend edge-to-edge. The window width includes 2× this on top of the regular
    /// `contentWidth`, so TGVs keep their natural width and gain a visible gutter on each side.
    static let sectionContentHorizontalMargin = CGFloat(15)
    static let sidebarActionButtonHeight: CGFloat = {
        let button = NSButton(title: " ", target: nil, action: nil)
        button.bezelStyle = .rounded
        return button.fittingSize.height
    }()
    private static let sidebarWidth = CGFloat(175)
    /// Outer left pad between the splitview divider and the TableGroupView background. Kept
    /// symmetric with `contentTrailingPadding` so the visible TGV "shoulders" match on both sides.
    private static let contentHorizontalPadding = CGFloat(5)
    /// Trailing pad between the TableGroupView and the window edge. The visible gap from the
    /// right-most control to the window edge is `contentTrailingPadding + TableGroupView.padding`
    /// (= 5 + 10 = 15pt), since `TableGroupView` adds ~10pt of internal padding on the right of
    /// each row's content.
    private static let contentTrailingPadding = CGFloat(5)
    private static let contentTopPadding = CGFloat(0)
    private static let topSectionTitlePadding = CGFloat(20)
    private static let contentBottomPadding = CGFloat(20)
    static let sectionTitleSpacing = CGFloat(10)
    private static let sectionInterSectionSpacing = CGFloat(15)
    private static let sectionBottomSpacing = CGFloat(30) - sectionInterSectionSpacing
    private static let sectionScrollTopPadding = CGFloat(20)
    private static let sectionSelectionTriggerRatioWhenScrollingDown = CGFloat(0.4)
    private static let sectionSelectionTriggerRatioWhenScrollingUp = CGFloat(0.6)
    private static let sectionSelectionDirectionDeltaThreshold = CGFloat(0.25)
    private static let minWindowHeight = CGFloat(400)
    private static let defaultWindowHeight = CGFloat(570)
    private static let sidebarTopInset = CGFloat(40)
    private static let sidebarHorizontalPadding = CGFloat(10)
    /// Padding inside the row's cell view between the cell's leading edge and the icon.
    /// `NSTableView.style = .sourceList` already inserts the cell content into its rounded
    /// highlight pill, so we only add a small visual breathing-room here.
    static let sidebarItemContentInset = CGFloat(4)
    private static let controlHighlightLayerName = "settingsSearchControlHighlight"
    private static let segmentedControlHighlightLayerName = "settingsSearchSegmentHighlight"
    private static let controlHighlightInset = CGFloat(1)
    private static let controlHighlightMinCornerRadius = CGFloat(4)
    private static let controlHighlightMaxCornerRadius = CGFloat(9)
    static var shared: SettingsWindow!

    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }

    private let splitViewController = NSSplitViewController()
    private let sidebarContainer = NSView()
    private let contentContainer = NSView()
    private let searchField = SidebarSearchField(frame: .zero)
    private let sidebarScrollView = NSScrollView()
    private let sidebarTableView = SidebarTableView()
    private let rightScrollView = NSScrollView()
    private let sectionsDocumentView = SettingsFlippedView(frame: .zero)
    private let sectionsStack = NSStackView()
    private let upgradeButton = UpgradeButton()
    private let quitButton = NSButton(title: String(format: NSLocalizedString("Quit %@", comment: "%@ is AltTab"), App.name), target: nil, action: #selector(NSApplication.terminate(_:)))
    private var sections = [SettingsSection]()
    private var visibleSections = [SettingsSection]()
    private var selectedSectionId: String?
    private var upgradeContentView: NSView?
    private var isShowingUpgradeView = false
    private var sectionsStackBottomConstraint: NSLayoutConstraint!
    private var upgradeViewBottomConstraint: NSLayoutConstraint?
    private var hasPlayedShine = false
    private var sheetHighlightTargets = [ObjectIdentifier: [SettingsSearchHighlightTarget]]()
    private var liveResizeOriginX: CGFloat?
    private var sectionSelectionTriggerRatio = SettingsWindow.sectionSelectionTriggerRatioWhenScrollingDown
    private var lastContentScrollY: CGFloat?
    private var isProgrammaticScrollInProgress = false

    convenience init() {
        // Leading pad is the title-to-divider gap; trailing pad is the card-outer-edge-to-window
        // gap. They're intentionally asymmetric because `TableGroupView`'s ~10pt internal padding
        // already adds a visual gap on the right — so the visible content sits roughly the same
        // distance from the window edge as the title sits from the divider.
        // Window width = sidebar + content + outer paddings + section's horizontal margins on
        // both sides. The section margins give TableGroupViews (gray-bg blocks) a visible gutter
        // on each side; without that extra width, narrower content (e.g. a TGV using
        // `contentWidth`) would leave dead space relative to wider content (e.g. the Controls
        // tab's sidebar+editor layout, which already consumes the full `contentWidth`).
        let windowWidth = Self.sidebarWidth + Self.contentWidth + Self.contentHorizontalPadding + Self.contentTrailingPadding + 2 * Self.sectionContentHorizontalMargin
        self.init(contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: Self.defaultWindowHeight),
                  styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        minSize = NSSize(width: windowWidth, height: Self.minWindowHeight)
        maxSize = NSSize(width: windowWidth, height: CGFloat.greatestFiniteMagnitude)
        setupWindow()
        setupView()
        // setFrameAutosaveNameSafely applies the persisted frame (dropping a corrupt one that would
        // otherwise abort the app) and returns whether a VALID saved frame existed — false on first
        // launch OR when the saved frame was corrupt, both of which should fall through to the default.
        let hasSavedFrame = setFrameAutosaveNameSafely("SettingsWindow")
        if !hasSavedFrame {
            // No saved frame → enforce the default size and center on the active screen. AppKit's
            // `init(contentRect:)` isn't load-bearing here because the unified toolbar can shift
            // the effective frame; setting `contentSize` explicitly is the safe path.
            setContentSize(NSSize(width: windowWidth, height: Self.defaultWindowHeight))
            center()
        }
        Self.shared = self
    }

    private func setupWindow() {
        delegate = self
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        if #available(macOS 11.0, *) {
            toolbarStyle = .unified
            titlebarSeparatorStyle = .none
        }
    }

    private func setupView() {
        setupSplitView()
        setupSidebar()
        setupContentPane()
        sectionDefinitions().forEach { addSection($0) }
        refreshControlsFromSettings()
        // Publish each section's dynamic search content (its rebuilt-after-build sidebar rows) now
        // that the section objects exist. Uses `self` directly — `SettingsWindow.shared` isn't
        // assigned until `init` finishes, so ControlsTab's own refresh calls no-op until then.
        sections.forEach { refreshSectionSearchContent($0.id) }
        applySearch("")
    }

    private func setupSplitView() {
        let sidebarVC = NSViewController()
        sidebarVC.view = sidebarContainer
        let contentVC = NSViewController()
        contentVC.view = contentContainer
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let contentItem = NSSplitViewItem(viewController: contentVC)
        splitViewController.splitViewItems = [sidebarItem, contentItem]
        splitViewController.splitView.dividerStyle = .thin
        contentViewController = splitViewController
    }

    private func setupSidebar() {
        setupSearchField(sidebarContainer)
        setupQuitButton(sidebarContainer)
        setupUpgradeButton(sidebarContainer)
        setupSidebarTable(sidebarContainer)
        // Match macOS System Settings: Tab cycles between the search field and the sidebar
        // table only. The nextValidKeyView overrides on these two subclasses keep AppKit's
        // chain walker from discovering inner sub-controls of the search field, scroll view,
        // or split view — without them we'd see 9 stops instead of 2.
        searchField.tabPeer = sidebarTableView
        sidebarTableView.tabPeer = searchField
    }

    private func setupContentPane() {
        rightScrollView.drawsBackground = false
        rightScrollView.hasVerticalScroller = true
        rightScrollView.hasHorizontalScroller = false
        rightScrollView.scrollerStyle = .overlay
        if #available(macOS 11.0, *) {
            rightScrollView.automaticallyAdjustsContentInsets = false
        }
        rightScrollView.contentInsets = NSEdgeInsetsZero
        rightScrollView.scrollerInsets = NSEdgeInsetsZero
        rightScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(rightScrollView)
        sectionsDocumentView.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.documentView = sectionsDocumentView
        sectionsStack.orientation = .vertical
        sectionsStack.spacing = 0
        sectionsStack.alignment = .leading
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        sectionsDocumentView.addSubview(sectionsStack)
        installContentScrollObserver()
        NSLayoutConstraint.activate([
            rightScrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            rightScrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            rightScrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            rightScrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            sectionsStack.topAnchor.constraint(equalTo: sectionsDocumentView.topAnchor, constant: Self.contentTopPadding),
            sectionsStack.leadingAnchor.constraint(equalTo: sectionsDocumentView.leadingAnchor, constant: Self.contentHorizontalPadding),
            sectionsStack.trailingAnchor.constraint(equalTo: sectionsDocumentView.trailingAnchor, constant: -Self.contentTrailingPadding),
            sectionsDocumentView.widthAnchor.constraint(equalTo: rightScrollView.contentView.widthAnchor),
        ])
        sectionsStackBottomConstraint = sectionsStack.bottomAnchor.constraint(equalTo: sectionsDocumentView.bottomAnchor, constant: -Self.contentBottomPadding)
        sectionsStackBottomConstraint.isActive = true
    }

    private func installContentScrollObserver() {
        rightScrollView.contentView.postsBoundsChangedNotifications = true
        lastContentScrollY = rightScrollView.contentView.bounds.minY
        NotificationCenter.default.addObserver(self, selector: #selector(contentViewBoundsDidChange), name: NSView.boundsDidChangeNotification, object: rightScrollView.contentView)
    }

    private func setupSearchField(_ parent: NSView) {
        searchField.delegate = self
        searchField.placeholderString = NSLocalizedString("Search", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) {
            searchField.controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            searchField.controlSize = .large
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: parent.topAnchor, constant: Self.sidebarTopInset),
            searchField.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: Self.sidebarHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -Self.sidebarHorizontalPadding),
        ])
    }

    private func setupSidebarTable(_ parent: NSView) {
        sidebarScrollView.drawsBackground = false
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.scrollerStyle = .overlay
        sidebarTableView.headerView = nil
        sidebarTableView.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTableView.rowHeight = 30
        sidebarTableView.selectionHighlightStyle = .sourceList
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.focusRingType = .none
        sidebarTableView.usesAlternatingRowBackgroundColors = false
        if #available(macOS 11.0, *) {
            sidebarTableView.style = .sourceList
        }
        sidebarTableView.delegate = self
        sidebarTableView.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "SettingsSidebarColumn"))
        column.resizingMask = .autoresizingMask
        sidebarTableView.addTableColumn(column)
        sidebarScrollView.documentView = sidebarTableView
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(sidebarScrollView)
        NSLayoutConstraint.activate([
            sidebarScrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            // The scroll view sits flush to the sidebar edges. The `.sourceList` selection style
            // adds its own ~10pt internal inset for the row highlight pill, so the pill ends up
            // aligned with the search field (which itself is inset by `sidebarHorizontalPadding`
            // = 10pt). Insetting the scroll view here would compound that and push the highlight
            // too far in.
            sidebarScrollView.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            sidebarScrollView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: upgradeButton.topAnchor, constant: -10),
        ])
    }

    private func setupUpgradeButton(_ parent: NSView) {
        upgradeButton.target = self
        upgradeButton.action = #selector(upgradeButtonClicked)
        upgradeButton.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(upgradeButton)
        // Align with the sidebar source-list highlight: the scroll view sits flush against the
        // sidebar edges and `.sourceList` adds its own ~10pt internal inset, so the highlight
        // pill ends up at `sidebarHorizontalPadding` from each edge — same as the search field.
        // The upgrade button matches that same edge.
        let inset = Self.sidebarHorizontalPadding
        NSLayoutConstraint.activate([
            upgradeButton.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            upgradeButton.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -20),
            upgradeButton.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            upgradeButton.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
        ])
    }

    @objc private func upgradeButtonClicked() {
        showUpgradeView()
    }

    private func setupQuitButton(_ parent: NSView) {
        quitButton.toolTip = quitButton.title
        quitButton.bezelStyle = .rounded
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(quitButton)
        NSLayoutConstraint.activate([
            quitButton.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -10),
            quitButton.widthAnchor.constraint(lessThanOrEqualTo: parent.widthAnchor, constant: -Self.sidebarHorizontalPadding * 2),
        ])
    }

    private func sectionDefinitions() -> [SettingsSectionDefinition] {
        [
            SettingsSectionDefinition(id: "appearance", title: NSLocalizedString("Appearance", comment: ""), symbol: .paintpalette, builder: AppearanceTab.initTab, registerDynamicSearchContent: nil),
            SettingsSectionDefinition(id: "controls", title: NSLocalizedString("Controls", comment: ""), symbol: .command, builder: ControlsTab.initTab, registerDynamicSearchContent: ControlsTab.registerSidebarRowsSearchContent),
            SettingsSectionDefinition(id: "general", title: NSLocalizedString("General", comment: ""), symbol: .gearshape, builder: GeneralTab.initTab, registerDynamicSearchContent: nil),
            SettingsSectionDefinition(id: "exceptions", title: NSLocalizedString("Exceptions", comment: ""), symbol: .handRaised, builder: ExceptionsTab.initTab, registerDynamicSearchContent: nil),
        ]
    }

    private func sidebarImage(_ definition: SettingsSectionDefinition) -> NSImage {
        return NSImage.fromSymbol(definition.symbol, pointSize: 18)
    }

    private func addSection(_ definition: SettingsSectionDefinition) {
        // Wrap the tab's view construction in an `indexed { ... }` scope so that every factory
        // call inside (`LabelAndControl.makeDropdown`, `TableGroupView.makeText`, `ProBadgeView`,
        // etc.) pushes its searchable strings and highlight targets into a per-section `Builder`.
        // The harvested results become the section's `searchableStrings` / `highlightTargets`
        // directly — no second-pass walk over the view tree. The section title is also produced
        // here so its label registration is captured by the same indexed scope.
        let sectionTitleBox: (title: LightLabel, view: NSView)
        let (built, builder) = SettingsSearchIndex.indexed { () -> (title: LightLabel, view: NSView) in
            let sectionTitle = TableGroupView.makeText(definition.title, bold: true)
            sectionTitle.font = NSFont.systemFont(ofSize: 15, weight: .medium)
            sectionTitle.lineBreakMode = .byWordWrapping
            sectionTitle.maximumNumberOfLines = 0
            let view = definition.builder()
            return (sectionTitle, view)
        }
        sectionTitleBox = built
        let sectionTitle = sectionTitleBox.title
        let sectionView = sectionTitleBox.view
        let container = NSView()
        let spacer = NSView()
        container.addSubview(sectionTitle)
        container.addSubview(sectionView)
        container.addSubview(spacer)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        sectionView.translatesAutoresizingMaskIntoConstraints = false
        spacer.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        let titleTopConstraint = sectionTitle.topAnchor.constraint(equalTo: container.topAnchor)
        let interSectionSpacingConstraint = spacer.topAnchor.constraint(equalTo: sectionView.bottomAnchor, constant: Self.sectionInterSectionSpacing)
        let spacerHeightConstraint = spacer.heightAnchor.constraint(equalToConstant: Self.sectionBottomSpacing)
        NSLayoutConstraint.activate([
            titleTopConstraint,
            // Section title sits at the section content's left margin + the TableGroupView's
            // internal padding — i.e., the same x as the row content text inside the TGV below
            // it. The TGV itself is inset by `sectionContentHorizontalMargin`; the title needs
            // to also account for the TGV's internal `TableGroupView.padding` so they line up.
            sectionTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.sectionContentHorizontalMargin + TableGroupView.padding),
            sectionTitle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sectionView.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: Self.sectionTitleSpacing),
            // 15pt horizontal margin between the section's left/right and the TGV's rounded
            // background, so the gray-bg block floats inside the section instead of touching
            // the splitview divider / window edge.
            sectionView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.sectionContentHorizontalMargin),
            sectionView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -Self.sectionContentHorizontalMargin),
            interSectionSpacingConstraint,
            spacer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            spacer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spacer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            spacerHeightConstraint,
        ])
        sectionsStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true
        // Inline-registered strings/targets are the source of truth; `collectSearchContent` still
        // runs as a safety net to catch direct widget creation in tabs (NSTextField, NSButton
        // etc. created outside the LabelAndControl/TableGroupView factories) that hasn't been
        // migrated to inline registration yet. The walk's results get unioned in via `Set` below.
        // Sections that manage rebuilt-after-build sidebar rows (`registerDynamicSearchContent`)
        // skip those rows here and publish them as dynamic content instead — see that hook.
        let skipSidebarRows = definition.registerDynamicSearchContent != nil
        var (searchableStrings, highlightTargets) = collectSearchContent(sectionTitle, sectionView, skipSidebarRows: skipSidebarRows)
        searchableStrings.append(contentsOf: builder.strings)
        highlightTargets.append(contentsOf: builder.targets)
        let search = SettingsSectionSearchContent(strings: Array(Set(searchableStrings)), targets: highlightTargets)
        let section = SettingsSection(definition.id,
                                      definition.title,
                                      sidebarImage(definition),
                                      container,
                                      sectionTitle,
                                      search,
                                      definition.registerDynamicSearchContent,
                                      interSectionSpacingConstraint,
                                      spacerHeightConstraint,
                                      titleTopConstraint)
        sections.append(section)
    }

    /// Re-publish a section's dynamic search content (its sidebar rows) into the index. A section's
    /// rows are rebuilt *outside* the build-time `indexed { }` scope (e.g. ControlsTab's
    /// `refreshShortcutRows` from the +/- buttons, a recorder edit, an input-source change, or the
    /// pro-lock observer), so the rows' own `registerSearchContent` no-ops there. This re-opens a
    /// scope, re-registers the *current* rows, and swaps them into the section wholesale — no stale
    /// targets for removed rows, and freshly-added rows become searchable. Re-applies the active
    /// query so rebuilt rows light up immediately. Called once per section at the end of
    /// `setupView`, then by the owning tab after every rebuild.
    func refreshSectionSearchContent(_ id: String) {
        guard let section = sections.first(where: { $0.id == id }),
              let register = section.registerDynamicSearchContent else { return }
        let (_, builder) = SettingsSearchIndex.indexed { register() }
        section.setDynamicSearchContent(builder.strings, builder.targets)
        if !SettingsSearch.isQueryEmpty(searchField.stringValue) {
            applySearch(searchField.stringValue)
        }
    }

    private func updateVisibleSectionsSpacing() {
        visibleSections.enumerated().forEach { index, section in
            let isFirst = index == 0
            let isLast = index == visibleSections.count - 1
            section.titleTopConstraint.constant = isFirst ? Self.topSectionTitlePadding : 0
            section.interSectionSpacingConstraint.constant = isLast ? 0 : Self.sectionInterSectionSpacing
            section.bottomSpacingConstraint.constant = isLast ? 0 : Self.sectionBottomSpacing
        }
    }

    private func collectSearchContent(_ sectionTitle: LightLabel, _ root: NSView, skipSidebarRows: Bool) -> ([String], [SettingsSearchHighlightTarget]) {
        var textValues = [String]()
        var highlightTargets = [SettingsSearchHighlightTarget]()
        textValues.append(sectionTitle.stringValue)
        if let target = SettingsSearchHighlight.highlightTarget(sectionTitle) {
            highlightTargets.append(target)
        }
        collectSearchContent(root, &textValues, &highlightTargets, skipSidebarRows: skipSidebarRows)
        return (Array(Set(textValues)), highlightTargets)
    }

    private func collectSearchContent(_ root: NSView,
                                      _ textValues: inout [String],
                                      _ highlightTargets: inout [SettingsSearchHighlightTarget],
                                      skipSidebarRows: Bool) {
        // Sections that rebuild their sidebar rows after construction publish those rows as dynamic
        // search content (see `refreshSectionSearchContent`). Skipping `SidebarListRow`s here keeps
        // targets for since-removed rows out of the section's fixed base — that staleness was the
        // "typing 'sho' no longer highlights Shortcut N" bug.
        if skipSidebarRows, root is SidebarListRow { return }
        if root is ProBadgeView {
            textValues.append(NSLocalizedString("Pro", comment: ""))
            return
        }
        if let textField = root as? NSTextField {
            let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
                if let target = SettingsSearchHighlight.highlightTarget(textField) {
                    highlightTargets.append(target)
                }
            }
        } else if let popUpButton = root as? NSPopUpButton {
            let value = popUpButton.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
            popUpButton.itemTitles.forEach {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    textValues.append(value)
                }
            }
            if let target = SettingsWindow.highlightTarget(popUpButton) {
                highlightTargets.append(target)
            }
        } else if let button = root as? NSButton {
            let value = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
            if let target = SettingsWindow.highlightTarget(button) {
                highlightTargets.append(target)
            }
        } else if let segmentedControl = root as? NSSegmentedControl {
            (0..<segmentedControl.segmentCount).forEach {
                let value = (segmentedControl.label(forSegment: $0) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    textValues.append(value)
                }
            }
            if let target = SettingsWindow.highlightTarget(segmentedControl) {
                highlightTargets.append(target)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            SettingsWindow.searchStrings(infoButton).forEach {
                textValues.append($0)
            }
            if let target = SettingsWindow.highlightTarget(infoButton) {
                highlightTargets.append(target)
            }
        } else if let textView = root as? NSTextView {
            let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
        }
        root.subviews.forEach { collectSearchContent($0, &textValues, &highlightTargets, skipSidebarRows: skipSidebarRows) }
    }

    static func highlightTarget(_ popUpButton: NSPopUpButton) -> SettingsSearchHighlightTarget? {
        controlHighlightTarget(popUpButton) {
            SettingsWindow.searchStrings(popUpButton)
        }
    }

    static func highlightTarget(_ button: NSButton) -> SettingsSearchHighlightTarget? {
        // Buttons that open one of the known sheets are search targets. Pre-build path: consult
        // the sheet class's static `searchableStrings`. Post-build path: also walk the live view
        // tree so any string the static list doesn't cover (or is added later inside the sheet)
        // still matches. Either path makes the button itself the visual highlight target — we
        // don't try to dive into the sheet's controls for in-sheet highlighting from out here.
        let staticStrings: [String]?
        if let action = button.action {
            staticStrings = SettingsSearchIndex.sheetSearchableStrings(forButtonAction: action)
        } else {
            staticStrings = nil
        }
        let hasSheet = SettingsWindow.sheet(forSearchButton: button) != nil
        guard staticStrings != nil || hasSheet else { return nil }
        return controlHighlightTarget(button) {
            var values = [String]()
            SettingsWindow.appendTrimmed(button.title, &values)
            if let staticStrings { values.append(contentsOf: staticStrings) }
            if let sheet = SettingsWindow.sheet(forSearchButton: button) {
                values.append(contentsOf: SettingsWindow.sheetSearchStrings(sheet))
            }
            return Array(Set(values))
        }
    }

    static func highlightTarget(_ segmentedControl: NSSegmentedControl) -> SettingsSearchHighlightTarget? {
        let segmentLabels = (0..<segmentedControl.segmentCount).map {
            SettingsWindow.trimmedText(segmentedControl.label(forSegment: $0) ?? "")
        }
        if segmentLabels.allSatisfy(\.isEmpty) { return nil }
        // For tab controls that surface different content per segment (the Filtering / Appearance
        // / Ordering toggle in ShortcutEditor — and the gesture editor's clone of the same), the
        // per-segment searchable strings are registered in `ControlsTab.tabSegmentSearchableStrings`.
        // A query that matches anything in a segment's content lights that segment up yellow —
        // including content for *unbuilt* panes (the Filtering/Appearance/Ordering panes are
        // constructed lazily, see `ShortcutEditor.ensurePaneBuilt`).
        let perSegmentStrings = ControlsTab.tabSegmentSearchableStrings[ObjectIdentifier(segmentedControl)]
        var matchingSegmentIndexes = [Int]()
        return SettingsSearchHighlightTarget({ query in
            matchingSegmentIndexes = []
            segmentLabels.enumerated().forEach { index, label in
                if !label.isEmpty, SettingsSearch.match(query, in: label) != nil {
                    matchingSegmentIndexes.append(index)
                    return
                }
                if let perSegmentStrings, index < perSegmentStrings.count,
                   perSegmentStrings[index].contains(where: { SettingsSearch.match(query, in: $0) != nil }) {
                    matchingSegmentIndexes.append(index)
                }
            }
            if matchingSegmentIndexes.isEmpty { return [] }
            return [0..<1]
        }, { _ in
            SettingsWindow.applySegmentedControlHighlight(to: segmentedControl, segmentIndexes: matchingSegmentIndexes)
        }, {
            SettingsWindow.clearSegmentedControlHighlight(from: segmentedControl)
        })
    }

    /// True iff any user-visible text in the view subtree matches `query`. Walks the same set of
    /// view types as `collectSearchContent` (text fields, popups, segmented controls, buttons,
    /// info popovers, text views) so the match semantics are consistent.
    private static func subtreeContainsMatch(_ view: NSView, query: String) -> Bool {
        if let tf = view as? NSTextField {
            let s = SettingsWindow.trimmedText(tf.stringValue)
            if !s.isEmpty, SettingsSearch.match(query, in: s) != nil { return true }
        } else if let pop = view as? NSPopUpButton {
            let title = SettingsWindow.trimmedText(pop.title)
            if !title.isEmpty, SettingsSearch.match(query, in: title) != nil { return true }
            for item in pop.itemTitles {
                let s = SettingsWindow.trimmedText(item)
                if !s.isEmpty, SettingsSearch.match(query, in: s) != nil { return true }
            }
        } else if let seg = view as? NSSegmentedControl {
            for i in 0..<seg.segmentCount {
                let s = SettingsWindow.trimmedText(seg.label(forSegment: i) ?? "")
                if !s.isEmpty, SettingsSearch.match(query, in: s) != nil { return true }
            }
        } else if let btn = view as? NSButton {
            let s = SettingsWindow.trimmedText(btn.title)
            if !s.isEmpty, SettingsSearch.match(query, in: s) != nil { return true }
        } else if let infoButton = view as? ClickHoverImageView {
            for s in SettingsWindow.searchStrings(infoButton) {
                if SettingsSearch.match(query, in: s) != nil { return true }
            }
        } else if let textView = view as? NSTextView {
            let s = SettingsWindow.trimmedText(textView.string)
            if !s.isEmpty, SettingsSearch.match(query, in: s) != nil { return true }
        }
        return view.subviews.contains { subtreeContainsMatch($0, query: query) }
    }

    static func highlightTarget(_ infoButton: ClickHoverImageView) -> SettingsSearchHighlightTarget? {
        controlHighlightTarget(infoButton) {
            SettingsWindow.searchStrings(infoButton)
        }
    }

    static func controlHighlightTarget(_ control: NSView, _ searchableStrings: @escaping () -> [String]) -> SettingsSearchHighlightTarget? {
        if searchableStrings().isEmpty { return nil }
        return SettingsSearchHighlightTarget({ query in
            searchableStrings().contains {
                SettingsSearch.match(query, in: $0) != nil
            }
        }, {
            SettingsWindow.applyControlHighlight(to: control)
        }, {
            SettingsWindow.clearControlHighlight(from: control)
        })
    }

    private static func clearControlHighlight(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == controlHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func clearSegmentedControlHighlight(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == segmentedControlHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func applySegmentedControlHighlight(to control: NSSegmentedControl, segmentIndexes: [Int]) {
        clearSegmentedControlHighlight(from: control)
        control.layoutSubtreeIfNeeded()
        guard !segmentIndexes.isEmpty else { return }
        control.wantsLayer = true
        let segmentRects = segmentedControlSegmentRects(control)
        segmentIndexes.forEach {
            guard segmentRects.indices.contains($0) else { return }
            // Inset only vertically. A horizontal inset visibly shrinks the highlight rect — for
            // adjacent segments it stops the yellow from reaching the segment boundary, leaving a
            // gray sliver between the highlight and the neighbour. Touching at the boundary looks
            // correct because the rounded corners curve inward at top/bottom anyway.
            let rect = segmentRects[$0].insetBy(dx: 0, dy: 1)
            guard rect.width > 0, rect.height > 0 else { return }
            let layer = noAnimation { CAShapeLayer() }
            layer.name = segmentedControlHighlightLayerName
            layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
            let cornerRadius = min(max(rect.height * 0.3, 4), 7)
            layer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            control.layer?.insertSublayer(layer, at: 0)
        }
    }

    private static func segmentedControlSegmentRects(_ control: NSSegmentedControl) -> [CGRect] {
        let segmentCount = control.segmentCount
        if segmentCount <= 0 { return [] }
        let widths = (0..<segmentCount).map { max(control.width(forSegment: $0), 0) }
        let explicitWidthTotal = widths.reduce(0) {
            $0 + ($1 > 0 ? $1 : 0)
        }
        let autoSegmentCount = widths.filter { $0 == 0 }.count
        let autoSegmentWidth = autoSegmentCount > 0 ? max(control.bounds.width - explicitWidthTotal, 0) / CGFloat(autoSegmentCount) : 0
        var currentX = control.bounds.minX
        return widths.enumerated().map { index, width in
            let resolvedWidth = width > 0 ? width : autoSegmentWidth
            let isLastSegment = index == segmentCount - 1
            let segmentWidth = isLastSegment ? max(control.bounds.maxX - currentX, 0) : resolvedWidth
            defer { currentX += segmentWidth }
            return CGRect(x: currentX, y: control.bounds.minY, width: segmentWidth, height: control.bounds.height)
        }
    }

    private static func applyControlHighlight(to view: NSView) {
        clearControlHighlight(from: view)
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        view.wantsLayer = true
        let layer = noAnimation { CAShapeLayer() }
        layer.name = controlHighlightLayerName
        layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
        let rect = view.bounds.insetBy(dx: -controlHighlightInset, dy: -controlHighlightInset)
        let cornerRadius = min(max(rect.height * 0.35, controlHighlightMinCornerRadius), controlHighlightMaxCornerRadius)
        layer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        view.layer?.insertSublayer(layer, at: 0)
    }

    private static func appendTrimmed(_ text: String, _ values: inout [String]) {
        let value = trimmedText(text)
        if !value.isEmpty {
            values.append(value)
        }
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func searchStrings(_ popUpButton: NSPopUpButton) -> [String] {
        var values = [String]()
        appendTrimmed(popUpButton.title, &values)
        popUpButton.itemTitles.forEach {
            appendTrimmed($0, &values)
        }
        return Array(Set(values))
    }

    private static func searchStrings(_ segmentedControl: NSSegmentedControl) -> [String] {
        var values = [String]()
        (0..<segmentedControl.segmentCount).forEach {
            appendTrimmed(segmentedControl.label(forSegment: $0) ?? "", &values)
        }
        return Array(Set(values))
    }

    private static func searchStrings(_ infoButton: ClickHoverImageView) -> [String] {
        var values = [String]()
        infoButton.searchableStrings.forEach {
            appendTrimmed($0, &values)
        }
        return Array(Set(values))
    }

    private static func sheet(forSearchButton button: NSButton) -> SheetWindow? {
        guard let action = button.action else { return nil }
        if action == #selector(AppearanceTab.showCustomizeStyleSheet) { return AppearanceTab.customizeStyleSheet }
        if action == #selector(AppearanceTab.showAnimationsSheet) { return AppearanceTab.animationsSheet }
        if action == #selector(ControlsTab.showShortcutsSettings) { return ControlsTab.shortcutsWhenActiveSheet }
        if action == #selector(ControlsTab.showAdditionalControlsSettings) { return ControlsTab.additionalControlsSheet }
        return nil
    }

    private static func sheetSearchStrings(_ sheet: SheetWindow) -> [String] {
        guard let contentView = sheet.contentView else { return [] }
        var values = [String]()
        collectSearchStrings(contentView, &values)
        return Array(Set(values))
    }

    private static func collectSearchStrings(_ root: NSView, _ values: inout [String]) {
        if let textField = root as? NSTextField {
            appendTrimmed(textField.stringValue, &values)
        } else if let popUpButton = root as? NSPopUpButton {
            appendTrimmed(popUpButton.title, &values)
            popUpButton.itemTitles.forEach {
                appendTrimmed($0, &values)
            }
        } else if let button = root as? NSButton {
            appendTrimmed(button.title, &values)
        } else if let segmentedControl = root as? NSSegmentedControl {
            (0..<segmentedControl.segmentCount).forEach {
                appendTrimmed(segmentedControl.label(forSegment: $0) ?? "", &values)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            searchStrings(infoButton).forEach {
                appendTrimmed($0, &values)
            }
        } else if let textView = root as? NSTextView {
            appendTrimmed(textView.string, &values)
        }
        root.subviews.forEach {
            collectSearchStrings($0, &values)
        }
    }

    private func refreshControlsFromSettings() {
        GeneralTab.refreshControlsFromPreferences()
    }

    func beginSheetWithSearchHighlight(_ sheet: SheetWindow) {
        beginSheet(sheet) { [weak self] _ in
            self?.clearSheetHighlights(sheet)
        }
        applySearchToSheet(sheet, searchField.stringValue)
    }

    private func applySearchToVisibleSheets(_ query: String) {
        sheets.compactMap { $0 as? SheetWindow }.forEach {
            applySearchToSheet($0, query)
        }
    }

    private func applySearchToSheet(_ sheet: SheetWindow, _ query: String) {
        let targets = highlightTargets(for: sheet)
        if SettingsSearch.isQueryEmpty(query) {
            targets.forEach { $0.clear() }
            return
        }
        targets.forEach { $0.updateHighlight(query) }
    }

    private func highlightTargets(for sheet: SheetWindow) -> [SettingsSearchHighlightTarget] {
        let key = ObjectIdentifier(sheet)
        if let targets = sheetHighlightTargets[key] {
            return targets
        }
        guard let contentView = sheet.contentView else { return [] }
        var targets = [SettingsSearchHighlightTarget]()
        collectSheetHighlightTargets(contentView, &targets)
        sheetHighlightTargets[key] = targets
        return targets
    }

    private func collectSheetHighlightTargets(_ root: NSView, _ targets: inout [SettingsSearchHighlightTarget]) {
        if let textField = root as? NSTextField {
            if let target = SettingsSearchHighlight.highlightTarget(textField) {
                targets.append(target)
            }
        } else if let popUpButton = root as? NSPopUpButton {
            if let target = SettingsWindow.highlightTarget(popUpButton) {
                targets.append(target)
            }
        } else if let segmentedControl = root as? NSSegmentedControl {
            if let target = SettingsWindow.highlightTarget(segmentedControl) {
                targets.append(target)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            if let target = SettingsWindow.highlightTarget(infoButton) {
                targets.append(target)
            }
        }
        root.subviews.forEach {
            collectSheetHighlightTargets($0, &targets)
        }
    }

    private func clearSheetHighlights(_ sheet: SheetWindow) {
        let key = ObjectIdentifier(sheet)
        guard let targets = sheetHighlightTargets[key] else { return }
        targets.forEach { $0.clear() }
    }

    @objc private func contentViewBoundsDidChange(_ notification: Notification) {
        guard !isShowingUpgradeView else { return }
        let currentY = rightScrollView.contentView.bounds.minY
        if isProgrammaticScrollInProgress {
            lastContentScrollY = currentY
            return
        }
        updateSectionSelectionTriggerRatio(currentY)
        guard let section = sectionAtCurrentScrollPosition(sectionSelectionTriggerRatio) else { return }
        guard selectedSectionId != section.id else { return }
        selectSection(section, scroll: false)
    }

    private func updateSectionSelectionTriggerRatio(_ currentY: CGFloat) {
        defer { lastContentScrollY = currentY }
        guard let lastContentScrollY else { return }
        let deltaY = currentY - lastContentScrollY
        if deltaY > Self.sectionSelectionDirectionDeltaThreshold {
            sectionSelectionTriggerRatio = Self.sectionSelectionTriggerRatioWhenScrollingDown
            return
        }
        if deltaY < -Self.sectionSelectionDirectionDeltaThreshold {
            sectionSelectionTriggerRatio = Self.sectionSelectionTriggerRatioWhenScrollingUp
        }
    }

    private func sectionAtCurrentScrollPosition(_ triggerRatio: CGFloat) -> SettingsSection? {
        guard !visibleSections.isEmpty else { return nil }
        let visibleBounds = rightScrollView.contentView.bounds
        let sectionTopY = visibleBounds.minY + visibleBounds.height * triggerRatio
        return visibleSections.last {
            $0.anchor.convert($0.anchor.bounds, to: sectionsDocumentView).minY <= sectionTopY
        } ?? visibleSections[0]
    }

    func navigateToSection(_ sectionId: String) {
        guard let section = sections.first(where: { $0.id == sectionId }) else { return }
        selectSection(section, scroll: true)
    }

    /// Run `changes` while preserving the user's scroll position. If the change in document height
    /// pushes the scroll origin, we compensate so the visible region stays put. Used by
    /// `AppearanceTab.refreshAllOverrideInfoLabels` when toggling override-info rows so the user's
    /// view doesn't jump.
    func preserveScrollPosition(during changes: () -> Void) {
        sectionsDocumentView.layoutSubtreeIfNeeded()
        let oldHeight = sectionsDocumentView.frame.height
        let oldY = rightScrollView.contentView.bounds.origin.y
        changes()
        sectionsDocumentView.layoutSubtreeIfNeeded()
        let delta = sectionsDocumentView.frame.height - oldHeight
        if oldY > 0 && delta != 0 {
            rightScrollView.contentView.scroll(to: NSPoint(x: 0, y: max(oldY + delta, 0)))
            rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
        }
    }

    func showUpgradeView() {
        guard !isShowingUpgradeView else { return }
        isShowingUpgradeView = true
        sidebarTableView.deselectAll(nil)
        selectedSectionId = nil
        sectionsStackBottomConstraint.isActive = false
        sectionsStack.isHidden = true
        if upgradeContentView == nil {
            let view = UpgradeTab.initTab()
            view.translatesAutoresizingMaskIntoConstraints = false
            sectionsDocumentView.addSubview(view)
            let bottomConstraint = view.bottomAnchor.constraint(equalTo: sectionsDocumentView.bottomAnchor, constant: -Self.contentBottomPadding)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: sectionsDocumentView.topAnchor, constant: Self.contentTopPadding + Self.topSectionTitlePadding),
                view.leadingAnchor.constraint(equalTo: sectionsDocumentView.leadingAnchor, constant: Self.contentHorizontalPadding + Self.sectionContentHorizontalMargin),
                view.trailingAnchor.constraint(lessThanOrEqualTo: sectionsDocumentView.trailingAnchor, constant: -(Self.contentTrailingPadding + Self.sectionContentHorizontalMargin)),
                bottomConstraint,
            ])
            upgradeViewBottomConstraint = bottomConstraint
            upgradeContentView = view
        } else {
            UpgradeTab.refreshStatus()
        }
        upgradeViewBottomConstraint?.isActive = true
        upgradeContentView?.isHidden = false
        isProgrammaticScrollInProgress = true
        defer { isProgrammaticScrollInProgress = false }
        rightScrollView.contentView.scroll(to: .zero)
        rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
        lastContentScrollY = 0
    }

    private func hideUpgradeView() {
        guard isShowingUpgradeView else { return }
        isShowingUpgradeView = false
        upgradeViewBottomConstraint?.isActive = false
        upgradeContentView?.isHidden = true
        sectionsStack.isHidden = false
        sectionsStackBottomConstraint.isActive = true
    }

    func refreshUpgradeButton() {
        upgradeButton.refreshTitle()
    }

    private func selectSection(_ section: SettingsSection, scroll: Bool, selectInSidebar: Bool = true) {
        hideUpgradeView()
        selectedSectionId = section.id
        if selectInSidebar, let row = visibleSections.firstIndex(where: { $0.id == section.id }), sidebarTableView.selectedRow != row {
            sidebarTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        guard scroll else { return }
        scrollToSection(section)
    }

    private func scrollToSection(_ section: SettingsSection) {
        guard isVisible else { return }
        sectionsDocumentView.layoutSubtreeIfNeeded()
        let anchorFrame = section.anchor.convert(section.anchor.bounds, to: sectionsDocumentView)
        let targetY = max(anchorFrame.minY - Self.sectionScrollTopPadding, 0)
        isProgrammaticScrollInProgress = true
        defer { isProgrammaticScrollInProgress = false }
        rightScrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
        lastContentScrollY = targetY
    }

    private func applySearch(_ query: String) {
        Popover.shared.updateSearchContext(query) { query, text in
            SettingsSearch.match(query, in: text)?.ranges ?? []
        }
        let hasQuery = !SettingsSearch.isQueryEmpty(query)
        let matchingSections = sections.filter { !hasQuery || $0.matches(query) }
        visibleSections = matchingSections
        let visibleSectionIds = Set(visibleSections.map(\.id))
        sections.forEach {
            let isVisible = visibleSectionIds.contains($0.id)
            $0.container.isHidden = !isVisible
            if isVisible && hasQuery {
                $0.highlightMatches(query)
            } else {
                $0.clearHighlights()
            }
        }
        applySearchToVisibleSheets(query)
        updateVisibleSectionsSpacing()
        sidebarTableView.reloadData()
        guard !visibleSections.isEmpty else {
            selectedSectionId = nil
            sidebarTableView.deselectAll(nil)
            return
        }
        if let selectedSectionId, let row = visibleSections.firstIndex(where: { $0.id == selectedSectionId }) {
            selectSection(visibleSections[row], scroll: true)
            return
        }
        selectSection(visibleSections[0], scroll: true)
    }

    override func close() {
        hasPlayedShine = false
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

extension SettingsWindow: NSWindowDelegate {
    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeOriginX = frame.origin.x
    }

    func windowDidResize(_ notification: Notification) {
        guard inLiveResize, let liveResizeOriginX else { return }
        guard abs(frame.origin.x - liveResizeOriginX) > 0 else { return }
        setFrameOrigin(NSPoint(x: liveResizeOriginX, y: frame.origin.y))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeOriginX = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // Trial day count is baked into `LicenseManager.state` and only recomputed on reassignment.
        // Refresh before the user reads the upgrade button / upgrade tab so the day count is current.
        LicenseManager.shared.refreshState()
        if isShowingUpgradeView {
            UpgradeTab.refreshStatus()
        }
        guard !hasPlayedShine else { return }
        hasPlayedShine = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.upgradeButton.playShineAnimation()
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Defer to the next runloop tick: tearing down view trees, removing observers,
        // and dropping the last strong ref to `self` while AppKit is still inside its own
        // close machinery causes objc_release crashes on re-entry.
        DispatchQueue.main.async {
            AppearanceTab.cleanup()
            ControlsTab.cleanup()
            GeneralTab.cleanup()
            ExceptionsTab.cleanup()
            UpgradeTab.cleanup()
            SettingsWindow.shared = nil
        }
    }
}

extension SettingsWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        applySearch(searchField.stringValue)
    }
}

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        30
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = visibleSections[row]
        let cell = tableView.makeView(withIdentifier: SettingsSidebarCellView.identifier, owner: self) as? SettingsSidebarCellView ?? {
            let view = SettingsSidebarCellView()
            view.identifier = SettingsSidebarCellView.identifier
            return view
        }()
        cell.configure(section)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        guard row >= 0, row < visibleSections.count else { return }
        let section = visibleSections[row]
        if selectedSectionId == section.id { return }
        selectSection(section, scroll: true, selectInSidebar: false)
    }
}
