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

/// Scrolling moves rows under a stationary cursor, and `NSTrackingArea` doesn't fire for that, so the
/// hovered row has to be recomputed on every bounds change. Pass the token from the previous call:
/// the list is rebuilt on tab rebuilds, and the old observer would otherwise watch a dead scroll view.
func observeSidebarListScroll(_ scrollView: NSScrollView, replacing previous: NSObjectProtocol?,
                              _ onScroll: @escaping () -> Void) -> NSObjectProtocol {
    if let previous {
        NotificationCenter.default.removeObserver(previous)
    }
    return NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
        object: scrollView.contentView, queue: .main) { _ in onScroll() }
}

/// The `SidebarListRow` under the cursor, or nil when the cursor is outside the list. Hit-testing
/// rather than tracking areas, so it stays right while the list scrolls under a still cursor.
func sidebarListRowAtCursor(_ scrollView: NSScrollView) -> SidebarListRow? {
    guard let window = scrollView.window else { return nil }
    let cursorInScrollView = scrollView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    guard scrollView.bounds.contains(cursorInScrollView) else { return nil }
    guard let documentView = scrollView.documentView else { return nil }
    let cursorInDocumentView = documentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    var current = documentView.hitTest(cursorInDocumentView)
    while let candidate = current {
        if let row = candidate as? SidebarListRow { return row }
        current = candidate.superview
    }
    return nil
}

class SidebarListContainer: SettingsCardView {
    enum ArrowDirection { case up, down }

    /// Optional keyboard navigation hook. When set, the container accepts first responder
    /// status and forwards up/down arrow key events to this callback.
    var onArrowKey: ((ArrowDirection) -> Void)?

    /// `drawsCard: false` is for a list that already sits inside a card, so cards don't nest.
    init(drawsCard: Bool = true) {
        super.init()
        layer?.masksToBounds = true
        if !drawsCard {
            fillColor = .clear
            borderColor = .clear
        }
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
}

class SidebarListRow: ClickHoverStackView {
    private static let selectionCornerRadius = CGFloat(7)
    private static let chevronImage = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
    private let iconView = NSImageView()
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private let titleLabel = NSTextField(labelWithString: "")
    private let titleRow = NSStackView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private let textColumn = NSStackView()
    private var proBadge: ProBadgeView?
    private var isSelectedRow = false
    private var isHoveredRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = SidebarListRow.selectionCornerRadius
        layer?.cornerCurve = .continuous
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
        chevronView.image = SidebarListRow.chevronImage
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.textColor = .labelColor
        summaryLabel.textColor = .secondaryLabelColor
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
        addArrangedSubview(chevronView)
        iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TableGroupView.padding).isActive = true
        textColumn.leadingAnchor.constraint(greaterThanOrEqualTo: iconView.trailingAnchor, constant: 8).isActive = true
        textColumn.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8).isActive = true
        chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -TableGroupView.padding).isActive = true
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
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

    /// Neutral pill, like the window's own sidebar: accent fills are kept for controls that pick a
    /// value, so navigation doesn't compete with them. `layer.backgroundColor` freezes the dynamic
    /// color, hence the re-run on appearance changes.
    private func updateStyle() {
        let backgroundColor: NSColor
        if isSelectedRow {
            backgroundColor = .unemphasizedSelectedContentBackgroundColor
        } else if isHoveredRow {
            backgroundColor = .tableHoverColor
        } else {
            backgroundColor = .clear
        }
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: isSelectedRow ? .semibold : .regular)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = backgroundColor.cgColor
        }
        chevronView.contentTintColor = isSelectedRow ? .secondaryLabelColor : .tertiaryLabelColor
    }
}
