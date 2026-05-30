import Cocoa

func sidebarSeparatorView() -> NSBox {
    let separator = NSBox()
    separator.boxType = .separator
    separator.translatesAutoresizingMaskIntoConstraints = false
    return separator
}

/// Builds the [sidebar | 1px separator | editor] horizontal chassis shared by ExceptionsTab and
/// ControlsTab. Callers are responsible for pinning a fixed width on `sidebar` and `editor`.
/// Sidebar and editor heights are tied (`sidebar.height == editor.height`), and the content is
/// pinned to all four edges of the returned `SidebarListContainer`.
func makeSidebarEditorContainer(sidebar: NSView, editor: NSView, minHeight: CGFloat? = nil) -> SidebarListContainer {
    let separator = sidebarSeparatorView()
    separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
    let content = NSStackView(views: [sidebar, separator, editor])
    content.orientation = .horizontal
    content.alignment = .top
    content.spacing = 0
    content.translatesAutoresizingMaskIntoConstraints = false
    sidebar.heightAnchor.constraint(equalTo: editor.heightAnchor).isActive = true
    let container = SidebarListContainer()
    container.widthAnchor.constraint(equalToConstant: SettingsWindow.contentWidth).isActive = true
    if let minHeight {
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
    }
    container.addSubview(content)
    NSLayoutConstraint.activate([
        content.topAnchor.constraint(equalTo: container.topAnchor),
        content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
}

class SidebarListContainer: NSView {
    enum ArrowDirection { case up, down }

    /// Optional keyboard navigation hook. When set, the container accepts first responder
    /// status and forwards up/down arrow key events to this callback.
    var onArrowKey: ((ArrowDirection) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = TableGroupView.cornerRadius
        layer?.borderWidth = TableGroupView.borderWidth
        layer?.masksToBounds = true
        refreshColors()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var acceptsFirstResponder: Bool { onArrowKey != nil }

    override func keyDown(with event: NSEvent) {
        guard let onArrowKey else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 126: onArrowKey(.up)
        case 125: onArrowKey(.down)
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        refreshColors()
    }

    private func refreshColors() {
        layer?.backgroundColor = NSColor.tableBackgroundColor.cgColor
        layer?.borderColor = NSColor.tableBorderColor.cgColor
    }
}

class SidebarListRow: ClickHoverStackView {
    private let iconView = NSImageView()
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private let titleLabel = DynamicColorTextField(labelWithString: "")
    private let titleRow = NSStackView()
    private let summaryLabel = DynamicColorTextField(labelWithString: "")
    private let chevronLabel = DynamicColorTextField(labelWithString: "›")
    private let textColumn = NSStackView()
    private var proBadge: ProBadgeView?
    private var isSelectedRow = false
    private var isHoveredRow = false
    private var windowObservers = [NSObjectProtocol]()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = TableGroupView.cornerRadius
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.isHidden = true
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 0
        textColumn.translatesAutoresizingMaskIntoConstraints = false
        let spacer = NSView()
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingHead
        titleLabel.cell?.usesSingleLineMode = true
        summaryLabel.alignment = .left
        summaryLabel.font = NSFont.systemFont(ofSize: 11)
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.cell?.usesSingleLineMode = true
        chevronLabel.font = NSFont.systemFont(ofSize: 22)
        chevronLabel.setContentHuggingPriority(.required, for: .horizontal)
        chevronLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.colorProvider = { [weak self] in self?.textColor(for: .title) ?? .labelColor }
        summaryLabel.colorProvider = { [weak self] in self?.textColor(for: .summary) ?? .secondaryLabelColor }
        chevronLabel.colorProvider = { [weak self] in self?.textColor(for: .chevron) ?? .secondaryLabelColor }
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addArrangedSubview(titleLabel)
        textColumn.addArrangedSubview(titleRow)
        textColumn.addArrangedSubview(summaryLabel)
        addArrangedSubview(iconView)
        addArrangedSubview(textColumn)
        addArrangedSubview(spacer)
        addArrangedSubview(chevronLabel)
        iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TableGroupView.padding).isActive = true
        textColumn.leadingAnchor.constraint(greaterThanOrEqualTo: iconView.trailingAnchor, constant: 8).isActive = true
        textColumn.trailingAnchor.constraint(lessThanOrEqualTo: chevronLabel.leadingAnchor, constant: -8).isActive = true
        chevronLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TableGroupView.padding).isActive = true
        updateStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    // The whole row is clickable. Without these overrides, clicks land on the inner labels
    // (NSTextField labels default to mouseDownCanMoveWindow = true), which lets
    // SettingsWindow.isMovableByWindowBackground drag the window from the row. Children are
    // display-only labels with no own click handling, so claiming the hit at the row is safe.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updateStyle()
            })
        }
        updateStyle()
    }

    /// Last bundle ID for which the row has been fully resolved (icon + display name).
    /// Consumers can compare against this to avoid redundant placeholder/refetch flashes.
    private(set) var resolvedToken: String?

    func setContent(_ title: String, _ summary: String) {
        titleLabel.stringValue = title
        summaryLabel.stringValue = summary
        toolTip = summary.isEmpty ? title : "\(title)\n\(summary)"
    }

    /// Register the row's current title + summary text into the active `SettingsSearchIndex.Builder`
    /// (if any), along with highlight targets for both labels. Call this *after* `setContent` so the
    /// indexed strings match what the user sees. A no-op outside an `indexed { ... }` scope.
    ///
    /// Sidebar rows are rebuilt *after* the section's build-time `indexed` scope (ControlsTab's
    /// `refreshShortcutRows`), so they can't register themselves at creation — there's no active
    /// builder. Instead the owning tab re-publishes all its rows through
    /// `SettingsWindow.refreshSectionSearchContent`, which re-opens an `indexed { ... }` scope and
    /// calls this on each current row (at build time and after every rebuild). The build-time walk
    /// deliberately skips `SidebarListRow`s so those rows live solely in the section's replaceable
    /// dynamic content — no stale targets for since-removed rows. Targets read the labels'
    /// `stringValue` live, so in-place content edits don't need re-registration.
    func registerSearchContent() {
        SettingsSearchIndex.registerString(titleLabel.stringValue)
        SettingsSearchIndex.registerString(summaryLabel.stringValue)
        SettingsSearchIndex.registerTarget(SettingsSearchHighlight.highlightTarget(titleLabel))
        SettingsSearchIndex.registerTarget(SettingsSearchHighlight.highlightTarget(summaryLabel))
    }

    /// Updates only the summary line, leaving title/icon untouched. Use when the underlying
    /// data changed in a way that only affects the summary (e.g. dropdown selection changed
    /// but app identity is the same).
    func setSummary(_ summary: String) {
        summaryLabel.stringValue = summary
        let title = titleLabel.stringValue
        toolTip = summary.isEmpty ? title : "\(title)\n\(summary)"
    }

    func markResolved(token: String) {
        resolvedToken = token
    }

    func setIcon(_ image: NSImage?, size: CGFloat = 32) {
        if let image {
            iconView.image = image
            iconView.isHidden = false
            iconWidthConstraint?.isActive = false
            iconHeightConstraint?.isActive = false
            let w = iconView.widthAnchor.constraint(equalToConstant: size)
            let h = iconView.heightAnchor.constraint(equalToConstant: size)
            w.isActive = true
            h.isActive = true
            iconWidthConstraint = w
            iconHeightConstraint = h
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
    }

    func setSelected(_ selected: Bool) {
        isSelectedRow = selected
        updateStyle()
    }

    func setHovered(_ hovered: Bool) {
        isHoveredRow = hovered
        updateStyle()
    }

    func setProBadge(_ show: Bool) {
        // No-op if already in the requested state. Rows are recycled across refreshes, so this is
        // called repeatedly with the same value; without this guard each call would leave the old
        // (now badge-less) `wrapper` in `titleRow` and append a new one — the wrappers pile up,
        // each adding `titleRow.spacing`, progressively squeezing and truncating the title.
        guard show != (proBadge != nil) else { return }
        // Remove the whole wrapper from `titleRow`, not just the badge from the wrapper.
        proBadge?.superview?.removeFromSuperview()
        proBadge = nil
        if show {
            let badge = ProBadgeView()
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                badge.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
                badge.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor, constant: 1),
                wrapper.heightAnchor.constraint(equalTo: badge.heightAnchor),
            ])
            titleRow.addArrangedSubview(wrapper)
            proBadge = badge
        }
    }

    private var isWindowKey: Bool { window?.isKeyWindow ?? false }

    private enum LabelRole { case title, summary, chevron }

    /// We have to branch on `isWindowKey` ourselves because `layer.backgroundColor` takes a
    /// `CGColor`, which freezes the semantic NSColor at the moment of assignment — it doesn't
    /// auto-resolve to its inactive variant later. The window key-state observer in
    /// `viewDidMoveToWindow` calls `updateStyle()` whenever the window gains or loses key,
    /// re-running this branch with the now-current state. Same pattern AppKit uses for table
    /// cells in source-list style.
    private func textColor(for role: LabelRole) -> NSColor {
        if isSelectedRow {
            // Key: white text on the accent-colored row. Non-key: revert to label color so the
            // text stays readable against the gray unemphasized selection background.
            return isWindowKey ? .alternateSelectedControlTextColor : .labelColor
        }
        switch role {
            case .title: return .labelColor
            case .summary, .chevron: return .secondaryLabelColor
        }
    }

    private func updateStyle() {
        let isKey = isWindowKey
        let selectedBackground: NSColor
        if #available(macOS 10.14, *) {
            // `controlAccentColor` matches the blue NSSegmentedControl uses for its selected
            // segment, so the shortcut sidebar selection visually lines up with the
            // Filtering / Appearance tabs and the segmented buttons above.
            // `unemphasizedSelectedContentBackgroundColor` is what AppKit table cells fall back
            // to when the window isn't key.
            selectedBackground = isKey ? .controlAccentColor : .unemphasizedSelectedContentBackgroundColor
        } else {
            selectedBackground = isKey ? .systemAccentColor : .lightGray
        }
        let backgroundColor: NSColor
        if isSelectedRow {
            backgroundColor = selectedBackground
        } else if isHoveredRow {
            backgroundColor = selectedBackground.withAlphaComponent(0.14)
        } else {
            backgroundColor = .clear
        }
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: isSelectedRow ? .semibold : .regular)
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        layer?.backgroundColor = backgroundColor.cgColor
        NSAppearance.current = previousAppearance
        titleLabel.needsDisplay = true
        summaryLabel.needsDisplay = true
        chevronLabel.needsDisplay = true
        proBadge?.setSelected(isSelectedRow && isKey)
    }
}
