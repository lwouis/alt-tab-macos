import Cocoa

class ExceptionEditorView: NSView {
    private var entry: ExceptionEntry = ExceptionEntry(bundleIdentifier: "", hide: .none, ignore: .none, windowTitleContains: nil)
    private var onChange: ((ExceptionEntry) -> Void)?
    /// Last bundle ID for which the header (icon + name) has been fully resolved. Used to avoid
    /// the placeholder-then-fetch flash when binding to a different entry that happens to share
    /// the same bundle ID, or when refreshing for non-bundle-id edits.
    private var resolvedHeaderBundleId: String?

    private let outerStack = NSStackView()
    private let headerIconView = NSImageView()
    private let headerNameLabel = NSTextField(labelWithString: "")
    private let bundleIdField = NSTextField(string: "")
    private let hideDropdown = PopupButtonLikeSystemSettings()
    private let ignoreDropdown = PopupButtonLikeSystemSettings()
    private var patternsRow: NSView?
    private var patternsListStack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func bind(to entry: ExceptionEntry, onChange: @escaping (ExceptionEntry) -> Void) {
        self.entry = entry
        self.onChange = onChange
        outerStack.isHidden = false
        refreshFromEntry()
    }

    func clear() {
        outerStack.isHidden = true
    }

    private func setupLayout() {
        outerStack.orientation = .vertical
        outerStack.alignment = .leading
        outerStack.spacing = 18
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        let header = makeHeader()
        let group = makeBehaviorGroup()

        outerStack.addArrangedSubview(header)
        outerStack.addArrangedSubview(group)

        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            // Force the behavior card to fill the editor's full width so its rows can extend to the
            // right edge. NSStackView's .leading alignment leaves it at intrinsic width otherwise.
            group.trailingAnchor.constraint(equalTo: outerStack.trailingAnchor),
        ])
    }

    private func makeHeader() -> NSView {
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        headerIconView.imageScaling = .scaleProportionallyUpOrDown
        headerIconView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        headerIconView.heightAnchor.constraint(equalToConstant: 56).isActive = true

        headerNameLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        headerNameLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [headerIconView, headerNameLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeBehaviorGroup() -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.distribution = .fill
        rows.translatesAutoresizingMaskIntoConstraints = false

        let bundleRow = makeBundleIdRow()
        let hideRow = makeHideRow()
        let patternsRow = makePatternsRow()
        let ignoreRow = makeIgnoreRow()
        self.patternsRow = patternsRow

        addToGroup(rows, view: bundleRow, addSeparator: false)
        addToGroup(rows, view: hideRow, addSeparator: true)
        rows.addArrangedSubview(patternsRow)
        patternsRow.leadingAnchor.constraint(equalTo: rows.leadingAnchor).isActive = true
        patternsRow.trailingAnchor.constraint(equalTo: rows.trailingAnchor).isActive = true
        addToGroup(rows, view: ignoreRow, addSeparator: true)

        // An NSBox painted behind the rows draws the rounded card. Its `fillColor`/`borderColor`
        // are dynamic NSColors, so AppKit re-resolves them for Dark/Light on every redraw on its
        // own — no appearance observing, no manual repaint, no baked `.cgColor`. The box is a
        // background sibling (not the rows' container) so the stack drives the card's size.
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.cornerRadius = 8
        card.borderWidth = 1
        card.borderColor = .tableSeparatorColor
        card.fillColor = .tableBackgroundColor
        card.contentViewMargins = .zero
        card.translatesAutoresizingMaskIntoConstraints = false

        let group = NSView()
        group.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(card)
        group.addSubview(rows)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: group.topAnchor),
            card.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: group.bottomAnchor),
            rows.topAnchor.constraint(equalTo: group.topAnchor),
            rows.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: group.bottomAnchor),
        ])
        return group
    }

    private func addToGroup(_ group: NSStackView, view: NSView, addSeparator: Bool) {
        if addSeparator {
            let sep = makeSeparator()
            group.addArrangedSubview(sep)
            sep.leadingAnchor.constraint(equalTo: group.leadingAnchor).isActive = true
            sep.trailingAnchor.constraint(equalTo: group.trailingAnchor).isActive = true
        }
        group.addArrangedSubview(view)
        view.leadingAnchor.constraint(equalTo: group.leadingAnchor).isActive = true
        view.trailingAnchor.constraint(equalTo: group.trailingAnchor).isActive = true
    }

    private func makeSeparator() -> NSView {
        // NSBox's native separator adapts to Dark/Light by itself (same as `sidebarSeparatorView()`).
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return sep
    }

    private func makeBundleIdRow() -> NSView {
        let label = makeRowLabel(NSLocalizedString("Bundle ID", comment: ""))
        bundleIdField.translatesAutoresizingMaskIntoConstraints = false
        bundleIdField.placeholderString = NSLocalizedString("e.g. com.example.app", comment: "")
        bundleIdField.cell?.sendsActionOnEndEditing = true
        bundleIdField.target = self
        bundleIdField.action = #selector(bundleIdChanged(_:))
        bundleIdField.lineBreakMode = .byTruncatingHead
        bundleIdField.usesSingleLineMode = true
        return makeRow(label: label, control: bundleIdField, controlMinWidth: 200)
    }

    private func makeHideRow() -> NSView {
        let label = makeRowLabel(NSLocalizedString("Hide windows", comment: ""))
        hideDropdown.translatesAutoresizingMaskIntoConstraints = false
        hideDropdown.removeAllItems()
        hideDropdown.addItems(withTitles: ExceptionHidePreference.allCases.map { c -> String in
            c == .none ? NSLocalizedString("Don't hide", comment: "") : c.localizedString
        })
        hideDropdown.target = self
        hideDropdown.action = #selector(hideChanged(_:))
        return makeRow(label: label, control: hideDropdown)
    }

    private func makeIgnoreRow() -> NSView {
        let label = makeRowLabel(NSLocalizedString("Ignore shortcuts", comment: ""))
        ignoreDropdown.translatesAutoresizingMaskIntoConstraints = false
        ignoreDropdown.removeAllItems()
        ignoreDropdown.addItems(withTitles: ExceptionIgnorePreference.allCases.map { c -> String in
            c == .none ? NSLocalizedString("Never", comment: "") : c.localizedString
        })
        ignoreDropdown.target = self
        ignoreDropdown.action = #selector(ignoreChanged(_:))
        return makeRow(label: label, control: ignoreDropdown)
    }

    private func makePatternsRow() -> NSView {
        patternsListStack.orientation = .vertical
        patternsListStack.alignment = .leading
        patternsListStack.spacing = 4
        patternsListStack.translatesAutoresizingMaskIntoConstraints = false

        let addButton = NSButton(title: NSLocalizedString("Add a pattern", comment: ""), target: self, action: #selector(addPatternTapped))
        addButton.bezelStyle = .recessed
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.image = NSImage.fromSymbol(.plus, pointSize: 11)
        addButton.imagePosition = .imageLeading

        let column = NSStackView(views: [patternsListStack, addButton])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        // Indent under "Hide windows" to signify the hierarchy.
        column.edgeInsets = NSEdgeInsets(top: 4, left: TableGroupView.padding + 24, bottom: 12, right: TableGroupView.padding)
        return column
    }

    private func rebuildPatternsList() {
        patternsListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let initial = entry.windowTitleContains ?? []
        if initial.isEmpty {
            patternsListStack.addArrangedSubview(makePatternFieldRow(initial: ""))
        } else {
            for p in initial {
                patternsListStack.addArrangedSubview(makePatternFieldRow(initial: p))
            }
        }
    }

    private func makePatternFieldRow(initial: String) -> NSView {
        let field = NSTextField(string: initial)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = NSLocalizedString("e.g. Debug", comment: "")
        field.delegate = self
        field.usesSingleLineMode = true
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let removeButton = NSButton()
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .circular
        removeButton.isBordered = false
        removeButton.image = NSImage.fromSymbol(.minusCircleFill, pointSize: 14)
        if #available(macOS 10.14, *) { removeButton.contentTintColor = .tertiaryLabelColor }
        removeButton.imagePosition = .imageOnly
        removeButton.target = self
        removeButton.action = #selector(removePatternTapped(_:))
        removeButton.widthAnchor.constraint(equalToConstant: 18).isActive = true
        removeButton.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let row = NSStackView(views: [field, removeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeRow(label: NSTextField, control: NSView, controlMinWidth: CGFloat = 0) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        row.edgeInsets = NSEdgeInsets(top: 11, left: TableGroupView.padding, bottom: 11, right: TableGroupView.padding)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        if controlMinWidth > 0 {
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: controlMinWidth).isActive = true
        }
        return row
    }

    private func makeRowLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func refreshFromEntry() {
        let bundleId = entry.bundleIdentifier
        bundleIdField.stringValue = bundleId
        let hideIndex = entry.hide.index
        if hideIndex >= 0, hideIndex < hideDropdown.numberOfItems {
            hideDropdown.selectItem(at: hideIndex)
        }
        let ignoreIndex = entry.ignore.index
        if ignoreIndex >= 0, ignoreIndex < ignoreDropdown.numberOfItems {
            ignoreDropdown.selectItem(at: ignoreIndex)
        }
        rebuildPatternsList()
        updatePatternsVisibility()
        // Header icon/name only refresh if bundle ID actually changed since last resolution.
        if resolvedHeaderBundleId != bundleId {
            headerIconView.image = AppDisplayInfo.genericIcon
            headerNameLabel.stringValue = bundleId
            resolveHeaderAsync(for: bundleId)
        }
    }

    @objc private func bundleIdChanged(_ sender: NSTextField) {
        let newBundleId = sender.stringValue
        entry.bundleIdentifier = newBundleId
        emitChange()
        if resolvedHeaderBundleId != newBundleId {
            headerNameLabel.stringValue = newBundleId
            headerIconView.image = AppDisplayInfo.genericIcon
            resolveHeaderAsync(for: newBundleId)
        }
    }

    private func resolveHeaderAsync(for bundleId: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let info = AppDisplayInfo.resolve(bundleId: bundleId)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.entry.bundleIdentifier == bundleId else { return }
                self.headerIconView.image = info.icon
                self.headerNameLabel.stringValue = info.name
                self.resolvedHeaderBundleId = bundleId
            }
        }
    }

    @objc private func hideChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i >= 0 && i < ExceptionHidePreference.allCases.count {
            entry.hide = ExceptionHidePreference.allCases[i]
            updatePatternsVisibility()
            emitChange()
        }
    }

    @objc private func ignoreChanged(_ sender: NSPopUpButton) {
        let i = sender.indexOfSelectedItem
        if i >= 0 && i < ExceptionIgnorePreference.allCases.count {
            entry.ignore = ExceptionIgnorePreference.allCases[i]
            emitChange()
        }
    }

    @objc private func addPatternTapped() {
        let row = makePatternFieldRow(initial: "")
        patternsListStack.addArrangedSubview(row)
        if let stack = row as? NSStackView, let field = stack.arrangedSubviews.first as? NSTextField {
            field.window?.makeFirstResponder(field)
        }
        commitPatterns()
    }

    @objc private func removePatternTapped(_ sender: NSButton) {
        var view: NSView? = sender
        while let v = view, !(v is NSStackView && v.superview === patternsListStack) {
            view = v.superview
        }
        if let row = view {
            patternsListStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        if patternsListStack.arrangedSubviews.isEmpty {
            patternsListStack.addArrangedSubview(makePatternFieldRow(initial: ""))
        }
        commitPatterns()
    }

    private func commitPatterns() {
        let patterns = patternsListStack.arrangedSubviews.compactMap { row -> String? in
            guard let stack = row as? NSStackView, let field = stack.arrangedSubviews.first as? NSTextField else { return nil }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        entry.windowTitleContains = patterns.isEmpty ? nil : patterns
        emitChange()
    }

    private func updatePatternsVisibility() {
        let show = entry.hide == .windowTitleContains
        patternsRow?.isHidden = !show
    }

    private func emitChange() {
        onChange?(entry)
    }
}

extension ExceptionEditorView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        // Only pattern fields use this delegate; bundle ID field uses target/action.
        if field !== bundleIdField, isPatternField(field) {
            commitPatterns()
        }
    }

    private func isPatternField(_ field: NSTextField) -> Bool {
        var view: NSView? = field
        while let v = view {
            if v === patternsListStack { return true }
            view = v.superview
        }
        return false
    }
}
