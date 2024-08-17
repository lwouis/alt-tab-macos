import Cocoa

/// A custom view that organizes an array of views into a vertical stack to show the system like UI,
/// with specific handling for `TableGroupView` and other view types.
class TableGroupSetView: NSStackView {
    static let spacing = CGFloat(20)
    static let tableGroupSpacing = CGFloat(5)
    static let othersSpacing = CGFloat(10)
    static let titleTableGroupSpacing = CGFloat(30)
    static let padding = CGFloat(20)
    static let leftRightPadding = 2 * TableGroupSetView.padding

    var verticalViews = [NSView]()
    var originalViews = [NSView]()

    convenience init(originalViews: [NSView],
                     toolsViews: [NSView]? = nil,
                     spacing: CGFloat = TableGroupSetView.spacing,
                     tableGroupSpacing: CGFloat = TableGroupSetView.tableGroupSpacing,
                     othersSpacing: CGFloat = TableGroupSetView.othersSpacing,
                     padding: CGFloat = TableGroupSetView.padding,
                     othersAlignment: NSLayoutConstraint.Attribute = .trailing,
                     toolsAlignment: NSLayoutConstraint.Attribute = .centerX) {
        self.init(frame: .zero)
        self.spacing = spacing
        self.orientation = .vertical
        self.originalViews = originalViews

        var continuousTableGroups = [NSView]()
        var continuousOthers = [NSView]()

        var lastViewWasTableGroup = false

        for view in originalViews {
            if view is TableGroupView {
                if !lastViewWasTableGroup {
                    // Only reset other views if we are switching from non-TableGroupView to TableGroupView
                    addContinuousOthersToSetViews(&continuousOthers, views: &verticalViews, othersSpacing: othersSpacing, padding: padding, alignment: othersAlignment)
                }
                continuousTableGroups.append(view)
                lastViewWasTableGroup = true
            } else if view is IllustratedImageThemeView {
                lastViewWasTableGroup = false
                addContinuousTableGroupsToSetViews(&continuousTableGroups, views: &verticalViews, tableGroupSpacing: tableGroupSpacing, padding: padding)
                addContinuousOthersToSetViews(&continuousOthers, views: &verticalViews, othersSpacing: othersSpacing, padding: padding, alignment: othersAlignment)
                addToolsViewToSetViews([view], views: &verticalViews, padding: padding, alignment: toolsAlignment)
            } else {
                if lastViewWasTableGroup {
                    // Only reset table group views if we are switching from TableGroupView to non-TableGroupView
                    addContinuousTableGroupsToSetViews(&continuousTableGroups, views: &verticalViews, tableGroupSpacing: tableGroupSpacing, padding: padding)
                }
                continuousOthers.append(view)
                lastViewWasTableGroup = false
            }
        }

        // Ensure any remaining views are added
        addContinuousTableGroupsToSetViews(&continuousTableGroups, views: &verticalViews, tableGroupSpacing: tableGroupSpacing, padding: padding)
        addContinuousOthersToSetViews(&continuousOthers, views: &verticalViews, othersSpacing: othersSpacing, padding: padding, alignment: othersAlignment)

        if let toolsView = toolsViews {
            addToolsViewToSetViews(toolsView, views: &verticalViews, padding: padding, alignment: toolsAlignment)
        }
        if let lastStackView = verticalViews.last {
            lastStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding).isActive = true
        }
    }

    func addContinuousTableGroupsToSetViews(_ continuousTableGroups: inout [NSView],
                                            views: inout [NSView],
                                            tableGroupSpacing: CGFloat,
                                            padding: CGFloat) {
        if !continuousTableGroups.isEmpty {
            let stackView = NSStackView()
            stackView.orientation = .vertical
            stackView.spacing = tableGroupSpacing
            stackView.alignment = .leading

            continuousTableGroups.enumerated().forEach { (index, view) in
                if let tableGroupView = view as? TableGroupView, tableGroupView.title != nil {
                    var spacerHeight = CGFloat(0)
                    if index == 0 && !views.isEmpty {
                        // at first, height: spacing + padding
                        spacerHeight = TableGroupSetView.titleTableGroupSpacing - spacing
                    } else if index > 0 {
                        // inner, height: tableGroupSpacing + padding
                        spacerHeight = TableGroupSetView.titleTableGroupSpacing
                    }
                    let spacerView = NSView()
                    spacerView.translatesAutoresizingMaskIntoConstraints = false
                    spacerView.heightAnchor.constraint(equalToConstant: spacerHeight).isActive = true
                    stackView.addArrangedSubview(spacerView)
                    stackView.setCustomSpacing(0, after: spacerView)
                }
                stackView.addArrangedSubview(view)
                stackView.setCustomSpacing(0, after: view)
            }

            continuousTableGroups.removeAll()

            addArrangedSubview(stackView)
            setStackViewConstraints(stackView, isFirst: views.isEmpty, padding: padding, alignment: .leading)
            views.append(stackView)
        }
    }

    func addContinuousOthersToSetViews(_ continuousOthers: inout [NSView], views: inout [NSView], othersSpacing: CGFloat, padding: CGFloat, alignment: NSLayoutConstraint.Attribute) {
        if !continuousOthers.isEmpty {
            let stackView = NSStackView()
            stackView.orientation = .horizontal
            stackView.spacing = othersSpacing
            stackView.alignment = alignment
            stackView.setViews(continuousOthers, in: .leading)
            continuousOthers.removeAll()

            addArrangedSubview(stackView)
            setStackViewConstraints(stackView, isFirst: views.isEmpty, padding: padding, alignment: alignment)
            views.append(stackView)
        }
    }

    func addToolsViewToSetViews(_ originalViews: [NSView], views: inout [NSView], padding: CGFloat, alignment: NSLayoutConstraint.Attribute) {
        if !originalViews.isEmpty {
            let stackView = NSStackView()
            stackView.orientation = .horizontal
            stackView.spacing = TableGroupSetView.othersSpacing
            stackView.alignment = alignment
            stackView.setViews(originalViews, in: .leading)

            addArrangedSubview(stackView)
            setStackViewConstraints(stackView, isFirst: views.isEmpty, padding: padding, alignment: alignment)
            views.append(stackView)
        }
    }

    func setStackViewConstraints(_ stackView: NSStackView, isFirst: Bool, padding: CGFloat, alignment: NSLayoutConstraint.Attribute) {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        if isFirst {
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: padding).isActive = true
        }
        stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding).isActive = true
        stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding).isActive = true
    }
}

/// A custom component view that organizes titles and rows in a stack view format,
/// likes system settings UI, with configurable styles and events.
class TableGroupView: ClickHoverStackView {
    static let spacing = CGFloat(10)
    static let padding = CGFloat(10)
    static let rowIntraSpacing = CGFloat(5)
    static let backgroundColor = NSColor.lightGray.withAlphaComponent(0.1)
    static let borderColor = NSColor.lightGray.withAlphaComponent(0.2)
    static let cornerRadius = CGFloat(5)
    static let borderWidth = CGFloat(1)

    private var lastMouseEnteredRowInfo: RowInfo?

    var title: String?
    var subTitle: String?

    var width: CGFloat = 500
    let titleLabel = NSTextField(labelWithString: "")
    let subTitleLabel = NSTextField(labelWithString: "")
    let titleStackView = NSStackView()
    let headerStackView = NSStackView()
    var tableStackViews = [NSStackView]()

    private var rows = [RowInfo]()

    struct Row {
        let leftTitle: String
        let subTitle: String?
        let rightViews: [NSView]

        init(leftTitle: String, subTitle: String? = nil, rightViews: [NSView]) {
            self.leftTitle = leftTitle
            self.subTitle = subTitle
            self.rightViews = rightViews
        }
    }

    struct RowInfo {
        let id: Int
        let view: NSView
        var previousSeparator: NSView?
        var nextSeparator: NSView?

        init(id: Int, view: NSView, previousSeparator: NSView? = nil, nextSeparator: NSView? = nil) {
            self.id = id
            self.view = view
            self.previousSeparator = previousSeparator
            self.nextSeparator = nextSeparator
        }
    }

    init(title: String? = nil, subTitle: String? = nil, hasHeader: Bool = false, width: CGFloat = 500) {
        self.width = width
        self.title = title
        self.subTitle = subTitle
        super.init(frame: .zero)
        setupView(hasHeader: hasHeader)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView(hasHeader: Bool) {
        orientation = .vertical
        spacing = TableGroupView.spacing
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: self.width).isActive = true

        setupTitleView()
        if hasHeader {
            setupHeaderView()
        }
        setupTableView()
    }

    private func setupTitleView() {
        if title == nil && subTitle == nil { return }
        titleStackView.orientation = .vertical
        titleStackView.alignment = .left
        titleStackView.spacing = TableGroupView.rowIntraSpacing

        if let title = title {
            titleLabel.stringValue = title
            titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
            titleLabel.alignment = .left
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.maximumNumberOfLines = 0

            titleStackView.addArrangedSubview(titleLabel)
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.leadingAnchor.constraint(equalTo: titleStackView.leadingAnchor, constant: TableGroupView.padding).isActive = true
            titleLabel.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: -TableGroupView.padding).isActive = true

            // Ensure height adjusts to content by setting priorities
            titleLabel.setContentHuggingPriority(.required, for: .vertical)
            titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        } else {
            titleLabel.isHidden = true
        }

        if let subTitle = subTitle {
            subTitleLabel.stringValue = subTitle
            subTitleLabel.font = NSFont.systemFont(ofSize: 12)
            subTitleLabel.textColor = .gray
            subTitleLabel.alignment = .left
            subTitleLabel.lineBreakMode = .byWordWrapping
            subTitleLabel.maximumNumberOfLines = 0

            titleStackView.addArrangedSubview(subTitleLabel)
            subTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            subTitleLabel.leadingAnchor.constraint(equalTo: titleStackView.leadingAnchor, constant: TableGroupView.padding).isActive = true
            subTitleLabel.trailingAnchor.constraint(equalTo: titleStackView.trailingAnchor, constant: -TableGroupView.padding).isActive = true

            // Ensure height adjusts to content by setting priorities
            subTitleLabel.setContentHuggingPriority(.required, for: .vertical)
            subTitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
            // Calculate the fitting height for subLabel and activate the height constraint
            let subLabelHeight = calculateHeightForLabel(subTitleLabel, width: self.width - 2 * TableGroupView.padding)
            subTitleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: subLabelHeight).isActive = true
        } else {
            subTitleLabel.isHidden = true
        }
        addArrangedSubview(titleStackView)
        titleStackView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        titleStackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        titleStackView.topAnchor.constraint(equalTo: topAnchor).isActive = true
    }

    private func setupHeaderView()  {
        headerStackView.orientation = .horizontal
        headerStackView.alignment = .centerX
        headerStackView.spacing = TableGroupView.spacing

        addArrangedSubview(headerStackView)

        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        headerStackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
    }

    private func setupTableView() {
        addNewTable()
    }

    func addHeader(views: [NSView]) {
        headerStackView.setViews(views, in: .leading)
    }

    @discardableResult
    func addNewTable() -> NSStackView {
        let tableStackView = NSStackView()
        tableStackView.orientation = .vertical
        tableStackView.spacing = 0
        tableStackView.wantsLayer = true
        tableStackView.layer?.backgroundColor = TableGroupView.backgroundColor.cgColor
        tableStackView.layer?.cornerRadius = TableGroupView.cornerRadius
        tableStackView.layer?.borderColor = TableGroupView.borderColor.cgColor
        tableStackView.layer?.borderWidth = TableGroupView.borderWidth
        addArrangedSubview(tableStackView)
        tableStackViews.append(tableStackView)

        tableStackView.translatesAutoresizingMaskIntoConstraints = false
        tableStackView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        tableStackView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
//        tableStackView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
//
//        if tableStackViews.count > 1 {
//            let previous = tableStackViews[tableStackViews.count - 1]
//            if let bottomConstraint = previous.constraints.first(where: { $0.firstAttribute == .bottom }) {
//                previous.removeConstraint(bottomConstraint)
//            }
//        }
        return tableStackView
    }

    @discardableResult
    func addRow(_ row: Row, onClick: EventClosure? = nil, onMouseEntered: EventClosure? = nil, onMouseExited: EventClosure? = nil) -> RowInfo {
        return addRow(leftText: row.leftTitle, rightViews: row.rightViews, subText: row.subTitle,
                onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    @discardableResult
    func addRow(leftText: String? = nil, rightViews: NSView, subText: String? = nil,
                onClick: EventClosure? = nil,
                onMouseEntered: EventClosure? = nil,
                onMouseExited: EventClosure? = nil) -> RowInfo {
        return addRow(leftText: leftText, rightViews: [rightViews], subText: subText,
                onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    @discardableResult
    func addRow(tableIndex: Int = -1, leftText: String? = nil, rightViews: [NSView]? = nil, subText: String? = nil,
                isAddSeparator: Bool = true,
                onClick: EventClosure? = nil,
                onMouseEntered: EventClosure? = nil,
                onMouseExited: EventClosure? = nil) -> RowInfo {
        let rowView = createRowView()
        let mainRow = createMainRow(leftText: leftText, rightViews: rightViews)
        setMainRow(mainRow, in: rowView)

        if let subText = subText {
            let subLabel = createSubLabel(with: subText, rightViewsWidth: mainRow.arrangedSubviews[2].fittingSize.width)
            setSecondaryRow([subLabel], rowView: rowView, mainRow: mainRow)
        } else {
            mainRow.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -TableGroupView.padding).isActive = true
        }

        let tableStackView = tableIndex == -1 ? tableStackViews[tableStackViews.count - 1] : tableStackViews[tableIndex]
        return finalizeRow(tableStackView: tableStackView, rowView: rowView, isAddSeparator: isAddSeparator,
                onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    @discardableResult
    func addRow(tableIndex: Int = -1, leftViews: [NSView]? = nil, rightViews: [NSView]? = nil, secondaryViews: [NSView]? = nil,
                isAddSeparator: Bool = true,
                secondaryViewsOrientation: NSUserInterfaceLayoutOrientation = .horizontal,
                secondaryViewsAlignment: NSLayoutConstraint.Attribute = .leading,
                onClick: EventClosure? = nil,
                onMouseEntered: EventClosure? = nil,
                onMouseExited: EventClosure? = nil) -> RowInfo {
        let rowView = createRowView()
        let mainRow = createMainRow(leftViews: leftViews, rightViews: rightViews)
        setMainRow(mainRow, in: rowView)

        if let secondaryViews = secondaryViews {
            setSecondaryRow(secondaryViews, rowView: rowView, mainRow: mainRow, orientation: secondaryViewsOrientation, alignment: secondaryViewsAlignment)
        } else {
            mainRow.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -TableGroupView.padding).isActive = true
        }

        let tableStackView = tableIndex == -1 ? tableStackViews[tableStackViews.count - 1] : tableStackViews[tableIndex]
        return finalizeRow(tableStackView: tableStackView, rowView: rowView, isAddSeparator: isAddSeparator,
                onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
    }

    private func finalizeRow(tableStackView: NSStackView, rowView: ClickHoverStackView, isAddSeparator: Bool,
                             onClick: EventClosure?, onMouseEntered: EventClosure?, onMouseExited: EventClosure?) -> RowInfo {
        let previousSeparator = addSeparatorIfNeeded(tableStackView: tableStackView, below: rowView, isAddSeparator: isAddSeparator)

        let rowInfo = RowInfo(id: rows.count, view: rowView, previousSeparator: previousSeparator, nextSeparator: nil)
        rows.append(rowInfo)
        tableStackViews.last?.addArrangedSubview(rowView)

        updateRowCornerRadius()
        setRowViewEvents(rowView, onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)

        return rowInfo
    }

    private func createRowView() -> ClickHoverStackView {
        let rowView = ClickHoverStackView()
        rowView.orientation = .vertical
        rowView.alignment = .leading
        rowView.spacing = TableGroupView.rowIntraSpacing

        return rowView
    }

    static func makeText(_ leftText: String?, bold: Bool = false) -> NSTextField {
        let leftLabel = NSTextField(labelWithString: leftText ?? "")
        if bold {
            leftLabel.font = NSFont.boldSystemFont(ofSize: 13)
        }
        leftLabel.alignment = .left
        leftLabel.lineBreakMode = .byWordWrapping
        leftLabel.maximumNumberOfLines = 0
        return leftLabel
    }

    private func createMainRow(leftText: String?, rightViews: [NSView]?) -> NSStackView {
        let leftLabel = TableGroupView.makeText(leftText)
        return createMainRow(leftViews: [leftLabel], rightViews: rightViews)
    }

    private func createMainRow(leftViews: [NSView]?, rightViews: [NSView]?) -> NSStackView {
        let mainRow = NSStackView()
        mainRow.orientation = .horizontal
        mainRow.spacing = 0

        let spacer = NSView() // Spacer to fill the middle space

        let leftStackView = NSStackView()
        leftStackView.orientation = .horizontal
        leftStackView.alignment = .leading
        leftStackView.spacing = TableGroupView.spacing
        if let leftViews = leftViews {
            leftStackView.setViews(leftViews, in: .leading)
        }

        let rightStackView = NSStackView()
        rightStackView.orientation = .horizontal
        rightStackView.spacing = TableGroupView.spacing
        if let rightViews = rightViews {
            rightStackView.setViews(rightViews, in: .leading)
        }

        mainRow.addArrangedSubview(leftStackView)
        mainRow.addArrangedSubview(spacer)
        mainRow.addArrangedSubview(rightStackView)

        leftStackView.translatesAutoresizingMaskIntoConstraints = false
        rightStackView.translatesAutoresizingMaskIntoConstraints = false
        spacer.translatesAutoresizingMaskIntoConstraints = false

        leftStackView.leadingAnchor.constraint(equalTo: mainRow.leadingAnchor).isActive = true
        rightStackView.trailingAnchor.constraint(equalTo: mainRow.trailingAnchor).isActive = true
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true

        return mainRow
    }

    private func setMainRow(_ mainRow: NSStackView, in rowView: ClickHoverStackView) {
        rowView.addArrangedSubview(mainRow)
        mainRow.translatesAutoresizingMaskIntoConstraints = false
        mainRow.topAnchor.constraint(equalTo: rowView.topAnchor, constant: TableGroupView.padding).isActive = true
        mainRow.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: TableGroupView.padding).isActive = true
        mainRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -TableGroupView.padding).isActive = true
        mainRow.heightAnchor.constraint(equalToConstant: mainRow.fittingSize.height).isActive = true
    }

    private func createSubLabel(with text: String, rightViewsWidth: CGFloat) -> NSTextField {
        let subLabel = NSTextField(wrappingLabelWithString: text)
        subLabel.font = NSFont.systemFont(ofSize: 12)
        subLabel.textColor = .gray
        subLabel.alignment = .left
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 0
        subLabel.setContentHuggingPriority(.required, for: .vertical)
        subLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subLabel.translatesAutoresizingMaskIntoConstraints = false

        let subLabelHeight = calculateHeightForLabel(subLabel, width: self.width - 2 * TableGroupView.padding)
        subLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: subLabelHeight).isActive = true

        return subLabel
    }

    private func setSecondaryRow(_ secondaryRows: [NSView]?, rowView: ClickHoverStackView, mainRow: NSStackView,
                                 orientation: NSUserInterfaceLayoutOrientation = .horizontal,
                                 alignment: NSLayoutConstraint.Attribute = .leading) {
        let secondaryRow = NSStackView()
        secondaryRow.orientation = orientation
        secondaryRow.alignment = alignment
        secondaryRow.spacing = TableGroupView.rowIntraSpacing
        if let secondaryRows = secondaryRows {
            secondaryRow.setViews(secondaryRows, in: .leading)
        }

        rowView.addSubview(secondaryRow)
        secondaryRow.translatesAutoresizingMaskIntoConstraints = false
        secondaryRow.topAnchor.constraint(equalTo: mainRow.bottomAnchor, constant: TableGroupView.rowIntraSpacing).isActive = true
        secondaryRow.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -TableGroupView.padding).isActive = true
        switch alignment {
            case .leading:
                secondaryRow.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: TableGroupView.padding).isActive = true
                secondaryRow.trailingAnchor.constraint(lessThanOrEqualTo: rowView.trailingAnchor, constant: -TableGroupView.padding).isActive = true

            case .centerX:
                secondaryRow.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: TableGroupView.padding).isActive = true
                secondaryRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -TableGroupView.padding).isActive = true

            case .right:
                secondaryRow.leadingAnchor.constraint(lessThanOrEqualTo: rowView.leadingAnchor, constant: TableGroupView.padding).isActive = true
                secondaryRow.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -TableGroupView.padding).isActive = true

            default: break
        }
    }

    private func addSeparatorIfNeeded(tableStackView: NSStackView, below rowView: NSView, isAddSeparator: Bool = true) -> NSView? {
        guard !rows.isEmpty else { return nil }
        guard isAddSeparator else { return nil }

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = TableGroupView.borderColor.cgColor
        tableStackView.addArrangedSubview(separator)

        separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
        separator.centerXAnchor.constraint(equalTo: tableStackView.centerXAnchor).isActive = true
        adjustSeparatorWidth(separator: separator, isMouseInside: false)

        if var lastRow = rows.last {
            lastRow.nextSeparator = separator
            rows[rows.count - 1] = lastRow
        }
        return separator
    }

    private func setRowViewEvents(_ rowView: ClickHoverStackView, onClick: EventClosure?, onMouseEntered: EventClosure?, onMouseExited: EventClosure?) {
        rowView.onClick = { event, view in
            onClick?(event, view)
        }

        rowView.onMouseEntered = { event, view in
            if let onMouseEntered = onMouseEntered {
                if let rowInfo = self.rows.first(where: { $0.view === rowView }) {
                    self.lastMouseEnteredRowInfo = rowInfo
                    self.addMouseEnteredEffects(rowInfo)
                    onMouseEntered(event, view)
                }
            }
        }

        rowView.onMouseExited = { event, view in
            if let rowInfo = self.rows.first(where: { $0.view === rowView }) {
                self.addMouseExitedEffects(rowInfo)
                onMouseExited?(event, view)
            }
        }
    }

    func removeLastMouseEnteredEffects() {
        if let lastMouseEnteredRowInfo = lastMouseEnteredRowInfo {
            self.addMouseExitedEffects(lastMouseEnteredRowInfo)
        }
    }

    private func addMouseEnteredEffects(_ rowInfo: RowInfo) {
        rowInfo.view.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        self.adjustSeparatorWidth(separator: rowInfo.previousSeparator, isMouseInside: true)
        self.adjustSeparatorWidth(separator: rowInfo.nextSeparator, isMouseInside: true)
    }

    private func addMouseExitedEffects(_ rowInfo: RowInfo) {
        rowInfo.view.layer?.backgroundColor = NSColor.clear.cgColor
        self.adjustSeparatorWidth(separator: rowInfo.previousSeparator, isMouseInside: false)
        self.adjustSeparatorWidth(separator: rowInfo.nextSeparator, isMouseInside: false)
    }

    private func adjustSeparatorWidth(separator: NSView?, isMouseInside: Bool) {
        let width = isMouseInside ? self.width : (self.width - 2 * TableGroupView.padding)

        if let separator = separator {
            if let existingWidthConstraint = separator.constraints.first(where: { $0.firstAttribute == .width }) {
                separator.removeConstraint(existingWidthConstraint)
            }
            separator.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
    }

    func removeRow(byId id: Int) {
        if let index = rows.firstIndex(where: { $0.id == id }) {
            rows[index].view.removeFromSuperview()
            rows.remove(at: index)
            updateRowCornerRadius()
        }
    }

    private func calculateHeightForLabel(_ label: NSTextField, width: CGFloat) -> CGFloat {
        let fittingSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let boundingRect = label.attributedStringValue.boundingRect(with: fittingSize, options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(boundingRect.height)
    }

    private func updateRowCornerRadius() {
        guard !rows.isEmpty else { return }

        for (index, rowInfo) in rows.enumerated() {
            if #available(macOS 10.13, *) {
                rowInfo.view.layer?.cornerRadius = 0
                rowInfo.view.layer?.maskedCorners = []

                if index == 0 {
                    rowInfo.view.layer?.cornerRadius = TableGroupView.cornerRadius
                    rowInfo.view.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                }

                if index == rows.count - 1 {
                    rowInfo.view.layer?.cornerRadius = TableGroupView.cornerRadius
                    rowInfo.view.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                }
            }
        }
    }
}

class ClickHoverStackView: NSStackView {
    var onClick: EventClosure?
    var onMouseEntered: EventClosure?
    var onMouseExited: EventClosure?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        clickGesture.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(clickGesture)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?(event, self)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?(event, self)
    }

    @objc private func handleClick(_ sender: NSClickGestureRecognizer) {
        if let event = sender.view?.window?.currentEvent {
            onClick?(event, self)
        }
    }
}
