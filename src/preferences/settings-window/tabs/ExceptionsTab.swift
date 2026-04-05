import Cocoa

class ExceptionsTab {
    private static let sidebarWidth = CGFloat(280)
    private static let rowHeight = CGFloat(56)
    private static let iconSize = CGFloat(40)
    private static let minContainerHeight = CGFloat(470)
    private static let sidebarHorizontalPadding = TableGroupView.padding
    private static let editorTopBottomPadding = TableGroupView.padding
    private static let editorHorizontalPadding = TableGroupView.padding
    private static var editorWidth: CGFloat { SettingsWindow.contentWidth - sidebarWidth - 1 }
    private static var editorContentWidth: CGFloat { editorWidth - 2 * editorHorizontalPadding }

    private static var items: [ExceptionEntry] = []
    private static var selectedIndex = -1
    private static var rowsStack: NSStackView?
    private static var rows: [SidebarListRow] = []
    private static var rowsScrollView: NSScrollView?
    private static var rowsScrollObserver: NSObjectProtocol?
    private static var sidebarSection: SidebarListContainer?
    private static var editorView: ExceptionEditorView!
    private static var countButtons: NSSegmentedControl?

    static func initTab() -> NSView {
        items = Preferences.exceptions
        selectedIndex = items.isEmpty ? -1 : 0
        editorView = ExceptionEditorView()
        let view = makeContainer()
        refreshSidebarRows()
        refreshSelection()
        refreshCountButtons()
        return view
    }

    static func cleanup() {
        if let observer = rowsScrollObserver {
            NotificationCenter.default.removeObserver(observer)
            rowsScrollObserver = nil
        }
        items.removeAll()
        rows.removeAll()
        selectedIndex = -1
        rowsStack = nil
        rowsScrollView = nil
        sidebarSection = nil
        editorView = nil
        countButtons = nil
    }

    private static func makeContainer() -> NSView {
        let container = makeSidebarEditorContainer(sidebar: makeSidebar(), editor: makeEditorPane(), minHeight: minContainerHeight)
        return TableGroupSetView(originalViews: [container], padding: 0, bottomPadding: 0)
    }

    private static func makeSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth).isActive = true

        let listContainer = NSView()
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        let section = SidebarListContainer()
        sidebarSection = section
        section.onArrowKey = { direction in
            guard !items.isEmpty else { return }
            let next: Int
            switch direction {
            case .up: next = max(0, selectedIndex - 1)
            case .down: next = min(items.count - 1, selectedIndex + 1)
            }
            if next != selectedIndex {
                selectIndex(next)
            }
        }
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        rowsStack = rows

        let scrollView = ForwardingVerticalScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScrollElasticity = .none
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.usesPredominantAxisScrolling = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        let documentView = ForwardingVerticalDocumentView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        documentView.addSubview(rows)
        rowsScrollView = scrollView
        installHoverObserver(scrollView)

        section.addSubview(scrollView)
        listContainer.addSubview(section)

        let buttons = makeAddRemoveButtons()
        listContainer.addSubview(buttons)

        sidebar.addSubview(listContainer)
        NSLayoutConstraint.activate([
            listContainer.topAnchor.constraint(equalTo: sidebar.topAnchor),
            listContainer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            listContainer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            listContainer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            rows.topAnchor.constraint(equalTo: documentView.topAnchor),
            rows.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            section.topAnchor.constraint(equalTo: listContainer.topAnchor, constant: TableGroupView.padding),
            section.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: sidebarHorizontalPadding),
            section.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor, constant: -sidebarHorizontalPadding),
            section.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -TableGroupView.padding),
            scrollView.topAnchor.constraint(equalTo: section.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: section.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: section.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor, constant: sidebarHorizontalPadding),
            buttons.trailingAnchor.constraint(lessThanOrEqualTo: listContainer.trailingAnchor, constant: -sidebarHorizontalPadding),
            buttons.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor, constant: -TableGroupView.padding),
        ])
        return sidebar
    }

    private static func makeEditorPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(equalToConstant: editorWidth).isActive = true
        pane.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.topAnchor.constraint(equalTo: pane.topAnchor, constant: editorTopBottomPadding),
            // No leading padding: the card sits right after the separator. Visual gap from the
            // sidebar section comes from the sidebar's own trailing margin (TableGroupView.padding).
            editorView.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -editorHorizontalPadding),
            editorView.bottomAnchor.constraint(lessThanOrEqualTo: pane.bottomAnchor, constant: -editorTopBottomPadding),
        ])
        return pane
    }

    private static func makeAddRemoveButtons() -> NSView {
        let plus = NSImage.fromSymbol(.plus, pointSize: 11)
        let minus = NSImage.fromSymbol(.minus, pointSize: 11)
        let segments = NSSegmentedControl(images: [plus, minus], trackingMode: .momentary, target: self, action: #selector(countButtonClicked(_:)))
        segments.translatesAutoresizingMaskIntoConstraints = false
        segments.segmentStyle = .rounded
        segments.setWidth(28, forSegment: 0)
        segments.setWidth(28, forSegment: 1)
        countButtons = segments
        let row = NSStackView(views: [segments])
        row.orientation = .horizontal
        row.alignment = .leading
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    @objc private static func countButtonClicked(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        sender.selectedSegment = -1
        if segment == 0 {
            showAddMenu(near: sender)
        } else if segment == 1 {
            removeSelected()
        }
    }

    private static func showAddMenu(near sender: NSSegmentedControl) {
        let menu = NSMenu()
        let runningAppsItem = NSMenuItem(title: NSLocalizedString("Add a running app", comment: ""), action: nil, keyEquivalent: "")
        runningAppsItem.submenu = buildRunningAppsSubmenu()
        menu.addItem(runningAppsItem)
        let diskItem = NSMenuItem(title: NSLocalizedString("Add an app from disk", comment: ""), action: #selector(addFromDisk(_:)), keyEquivalent: "")
        diskItem.target = self
        menu.addItem(diskItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private static func addFromDisk(_ sender: NSMenuItem) {
        let dialog = NSOpenPanel()
        dialog.allowsMultipleSelection = false
        dialog.allowedFileTypes = ["app"]
        dialog.canChooseDirectories = false
        dialog.beginSheetModal(for: SettingsWindow.shared) {
            if $0 == .OK, let url = dialog.url, let bundleId = Bundle(url: url)?.bundleIdentifier {
                addException(bundleId)
            }
        }
    }

    private static func buildRunningAppsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        runningAppsForMenu().forEach { submenu.addItem(makeRunningAppItem($0.app, $0.bundleId)) }
        return submenu
    }

    private static func runningAppsForMenu() -> [(app: NSRunningApplication, bundleId: String)] {
        let existingIds = Set(items.map { $0.bundleIdentifier })
        var appsByBundleId = [String: NSRunningApplication]()
        runningAppCandidates().forEach {
            guard let bundleId = $0.bundleIdentifier, !existingIds.contains(bundleId), appsByBundleId[bundleId] == nil else { return }
            appsByBundleId[bundleId] = $0
        }
        return appsByBundleId.map { ($0.value, $0.key) }.sorted { appMenuTitle($0.app).localizedStandardCompare(appMenuTitle($1.app)) == .orderedAscending }
    }

    private static func runningAppCandidates() -> [NSRunningApplication] {
        Windows.list.map { $0.application.runningApplication } + NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private static func makeRunningAppItem(_ app: NSRunningApplication, _ bundleId: String) -> NSMenuItem {
        let item = NSMenuItem(title: appMenuTitle(app), action: #selector(addRunningApp(_:)), keyEquivalent: "")
        if let path = app.bundleURL?.path {
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        item.representedObject = bundleId
        item.target = self
        return item
    }

    private static func appMenuTitle(_ app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleIdentifier ?? ""
    }

    @objc private static func addRunningApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else { return }
        addException(bundleId)
    }

    private static func addException(_ bundleId: String) {
        if let existing = items.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            selectedIndex = existing
            refreshSelection()
            return
        }
        items.append(ExceptionEntry(bundleIdentifier: bundleId, hide: .always, ignore: .none, windowTitleContains: nil))
        savePreferences()
        selectedIndex = items.count - 1
        refreshSidebarRows()
        refreshSelection()
        refreshCountButtons()
    }

    private static func removeSelected() {
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        items.remove(at: selectedIndex)
        savePreferences()
        if items.isEmpty {
            selectedIndex = -1
        } else {
            selectedIndex = min(selectedIndex, items.count - 1)
        }
        refreshSidebarRows()
        refreshSelection()
        refreshCountButtons()
    }

    private static func savePreferences() {
        Preferences.set("exceptions", items)
    }

    private static func refreshSidebarRows() {
        guard let rowsStack else { return }
        setHoveredRow(nil)
        rowsStack.arrangedSubviews.forEach {
            rowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll(keepingCapacity: true)
        for index in 0..<items.count {
            let row = SidebarListRow()
            applyContent(row, index: index)
            row.setSelected(index == selectedIndex)
            row.onClick = { [weak row] _, _ in
                guard let row else { return }
                if let i = ExceptionsTab.rows.firstIndex(where: { $0 === row }) {
                    ExceptionsTab.selectIndex(i)
                }
                // Make the sidebar first responder so subsequent up/down arrows move selection.
                if let section = ExceptionsTab.sidebarSection {
                    section.window?.makeFirstResponder(section)
                }
            }
            row.onMouseEntered = { [weak row] _, _ in setHoveredRow(row) }
            row.onMouseExited = { _, _ in setHoveredRow(nil) }
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            rows.append(row)
            if index < items.count - 1 {
                let separator = sidebarSeparatorView()
                rowsStack.addArrangedSubview(separator)
                separator.leadingAnchor.constraint(equalTo: rowsStack.leadingAnchor, constant: TableGroupView.padding).isActive = true
                separator.trailingAnchor.constraint(equalTo: rowsStack.trailingAnchor, constant: -TableGroupView.padding).isActive = true
                separator.heightAnchor.constraint(equalToConstant: TableGroupView.borderWidth).isActive = true
            }
        }
        syncHoverState()
    }

    private static func applyContent(_ row: SidebarListRow, index: Int) {
        let entry = items[index]
        let bundleId = entry.bundleIdentifier
        let summary = summaryString(for: entry)
        // Already resolved for this bundle ID: just refresh the summary, leave icon/title alone.
        // Avoids the placeholder-then-resolve flash on edits that don't change app identity.
        if row.resolvedToken == bundleId {
            row.setSummary(summary)
            return
        }
        // BundleId changed (or first paint): show a synchronous placeholder, then resolve async.
        row.setIcon(AppDisplayInfo.genericIcon, size: iconSize)
        row.setContent(bundleId, summary)
        DispatchQueue.global(qos: .userInitiated).async {
            let info = AppDisplayInfo.resolve(bundleId: bundleId)
            DispatchQueue.main.async { [weak row] in
                guard let row else { return }
                guard let currentIndex = rows.firstIndex(where: { $0 === row }),
                      currentIndex < items.count,
                      items[currentIndex].bundleIdentifier == bundleId else { return }
                row.setIcon(info.icon, size: iconSize)
                row.setContent(info.name, summaryString(for: items[currentIndex]))
                row.markResolved(token: bundleId)
            }
        }
    }

    private static func selectIndex(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        selectedIndex = index
        refreshSelection()
        refreshCountButtons()
        if index < rows.count {
            rows[index].scrollToVisible(rows[index].bounds)
        }
    }

    private static func refreshSelection() {
        rows.enumerated().forEach { $1.setSelected($0 == selectedIndex) }
        if selectedIndex >= 0, selectedIndex < items.count {
            editorView.bind(to: items[selectedIndex]) { [weak rowsStack] updated in
                _ = rowsStack
                guard ExceptionsTab.selectedIndex >= 0, ExceptionsTab.selectedIndex < ExceptionsTab.items.count else { return }
                ExceptionsTab.items[ExceptionsTab.selectedIndex] = updated
                ExceptionsTab.savePreferences()
                if ExceptionsTab.selectedIndex < ExceptionsTab.rows.count {
                    ExceptionsTab.applyContent(ExceptionsTab.rows[ExceptionsTab.selectedIndex], index: ExceptionsTab.selectedIndex)
                }
            }
        } else {
            editorView.clear()
        }
    }

    private static func refreshCountButtons() {
        countButtons?.setEnabled(true, forSegment: 0)
        countButtons?.setEnabled(selectedIndex >= 0 && selectedIndex < items.count, forSegment: 1)
    }

    private static func summaryString(for entry: ExceptionEntry) -> String {
        var parts: [String] = []
        if entry.hide != .none {
            parts.append(NSLocalizedString("Hide", comment: ""))
        }
        if entry.ignore != .none {
            parts.append(NSLocalizedString("Ignore shortcuts", comment: ""))
        }
        return parts.joined(separator: " • ")
    }

    private static func installHoverObserver(_ scrollView: NSScrollView) {
        if let rowsScrollObserver {
            NotificationCenter.default.removeObserver(rowsScrollObserver)
        }
        rowsScrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { _ in
            syncHoverState()
        }
    }

    private static func setHoveredRow(_ row: SidebarListRow?) {
        rows.forEach { $0.setHovered($0 === row) }
    }

    private static func syncHoverState() {
        guard let rowsScrollView else { return }
        setHoveredRow(hoveredRowAtCursor(rowsScrollView))
    }

    private static func hoveredRowAtCursor(_ scrollView: NSScrollView) -> SidebarListRow? {
        guard let window = scrollView.window else { return nil }
        let cursorInScrollView = scrollView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard scrollView.bounds.contains(cursorInScrollView) else { return nil }
        guard let documentView = scrollView.documentView else { return nil }
        let cursorInDocumentView = documentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return enclosingSidebarRow(documentView.hitTest(cursorInDocumentView))
    }

    private static func enclosingSidebarRow(_ view: NSView?) -> SidebarListRow? {
        var current = view
        while let candidate = current {
            if let row = candidate as? SidebarListRow {
                return row
            }
            current = candidate.superview
        }
        return nil
    }
}

struct AppDisplayInfo {
    let name: String
    let icon: NSImage

    static let genericIcon: NSImage = NSWorkspace.shared.icon(forFileType: "app")

    static func resolve(bundleId: String) -> AppDisplayInfo {
        guard !bundleId.isEmpty else {
            return AppDisplayInfo(name: bundleId, icon: genericIcon)
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return fromBundle(at: url, fallbackName: bundleId)
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
           let path = running.bundleURL?.path {
            return AppDisplayInfo(name: running.localizedName ?? bundleId, icon: NSWorkspace.shared.icon(forFile: path))
        }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier ?? "").hasPrefix(bundleId)
        }), let path = running.bundleURL?.path {
            return AppDisplayInfo(name: bundleId, icon: NSWorkspace.shared.icon(forFile: path))
        }
        if let match = installedApps.first(where: { $0.bundleId.hasPrefix(bundleId) }) {
            return AppDisplayInfo(name: bundleId, icon: NSWorkspace.shared.icon(forFile: match.url.path))
        }
        return AppDisplayInfo(name: bundleId, icon: genericIcon)
    }

    private static func fromBundle(at url: URL, fallbackName: String) -> AppDisplayInfo {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let bundle = Bundle(url: url)
        let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? fallbackName
        return AppDisplayInfo(name: name, icon: icon)
    }

    // Cached on first access. Enumerates .app bundles in standard app directories.
    // .skipsPackageDescendants stops the enumerator from descending into .app packages but still
    // yields the .app URL itself, so nested apps (e.g. /Applications/Parallels/*.app) are found.
    private static let installedApps: [(bundleId: String, url: URL)] = {
        var apps: [(String, URL)] = []
        let dirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        for dir in dirs {
            guard let enumerator = fm.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension == "app", let bundleId = Bundle(url: item)?.bundleIdentifier else { continue }
                apps.append((bundleId, item))
            }
        }
        return apps
    }()
}
