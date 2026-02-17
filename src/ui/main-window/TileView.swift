import Cocoa

class TileView: FlippedView {
    static let noOpenWindowToolTip = NSLocalizedString("App is running but has no open window", comment: "")
    // when calculating the width of a nstextfield, somehow we need to add this suffix to get the correct width
    static let extraTextForPadding = "lmnopqrstuvw"

    var window_: Window?
    var thumbnail = LightImageLayer(withTransparencyChecks: true)
    var appIcon = LightImageLayer()
    var label = TileTitleView(font: Appearance.font)
    var statusIcons = StatusIconsView()
    var dockLabelIcon = TileFontIconView(badgeSize: TileFontIconView.badgeBaseSize(forIconSize: TileView.iconSize().width))
    var windowlessAppIndicator = WindowlessAppIndicator(tooltip: TileView.noOpenWindowToolTip)
    private var fullTitle = ""
    private var fullTitleWidth = CGFloat(0)

    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var indexInRecycledViews: Int!
    private var lastDragLocation: NSPoint?

    var isFirstInRow = false
    var isLastInRow = false
    var indexInRow = 0
    var numberOfViewsInRow = 0

    // for VoiceOver cursor
    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let location = sender.draggingLocation
        if location != lastDragLocation {
            lastDragLocation = location
            mouseMovedCallback()
        }
        return .link
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        lastDragLocation = sender.draggingLocation
        mouseMovedCallback()
        setDraggingTimer()
        return .link
    }

    private func setDraggingTimer() {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = Timer(timeInterval: 2, repeats: false, block: { [weak self] _ in
            guard let self else { return }
            // the user can tab to focus the next thumbnail, while still dragging. We don't want to perform drag then
            if Windows.selectedWindowIndex == Windows.hoveredWindowIndex {
                self.mouseUpCallback()
            }
        })
        dragAndDropTimer?.tolerance = 0.2
        if let dragAndDropTimer {
            // we need to target .common since dragging is running in .eventTracking on trackpad
            RunLoop.main.add(dragAndDropTimer, forMode: .common)
        }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        lastDragLocation = nil
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = nil
        App.app.tilesPanel.tilesView.thumbnailOverView.resetHoveredWindow()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = nil
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as! [URL]
        let appUrl = window_!.application.bundleURL!
        let open = try? NSWorkspace.shared.open(urls, withApplicationAt: appUrl, options: [], configuration: [:])
        App.app.hideUi()
        return open != nil
    }

    func mouseMoved() {
        updateLabelTooltipIfNeeded()
        mouseMovedCallback()
    }

    private func updateLabelTooltipIfNeeded() {
        guard Preferences.appearanceStyle != .appIcons else { return }
        label.toolTip = fullTitleWidth >= label.frame.size.width ? fullTitle : nil
    }

    convenience init() {
        self.init(frame: .zero)
        setupView()
        observeDragAndDrop()
    }

    /// The frame used by TileUnderLayer to position the highlight rectangle.
    /// In appIcons style, it covers appIcon + edge insets. Otherwise, it covers the full cell.
    var highlightFrame: CGRect {
        if Preferences.appearanceStyle == .appIcons {
            return CGRect(x: 0, y: 0,
                          width: frame.width, height: appIcon.frame.height + Appearance.edgeInsetsSize * 2)
        }
        return CGRect(origin: .zero, size: frame.size)
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        window_ = element
        label.toolTip = nil
        updateValues(element, index, newHeight)
        updateSizes(newHeight)
        updatePositions(newHeight)
        applySearchHighlight()
    }

    func drawHighlight() {
        if Preferences.appearanceStyle == .appIcons {
            let isFocused = indexInRecycledViews == Windows.selectedWindowIndex
            let isHovered = indexInRecycledViews == Windows.hoveredWindowIndex
            label.isHidden = !(isFocused || isHovered)
            updateAppIconsLabel(isFocused: isFocused, isHovered: isHovered)
        }
    }

    func updateDockLabelIcon(_ dockLabel: String?) {
        assignIfDifferent(&dockLabelIcon.isHidden, dockLabel == nil || Preferences.hideAppBadges || Appearance.iconSize == 0)
        if !dockLabelIcon.isHidden, let dockLabel {
            dockLabelIcon.setText(dockLabel)
            dockLabelIcon.setAccessibilityLabel(getAccessibilityTextForBadge(dockLabel))
        }
    }

    private func setupView() {
        setAccessibilityChildren([])
        wantsLayer = true
        layer!.masksToBounds = false // without this, label will be clipped in app-icons style since its larger than its parentView
        setupSharedSubviews()
        setupStyleSpecificSubviews()
    }

    private func setupSharedSubviews() {
        let shadow = TileView.makeShadow(Appearance.imagesShadowColor)
        let appIconShadow = TileView.makeAppIconShadow(Appearance.imagesShadowColor)
        let thumbnailShadow = TileView.makeThumbnailShadow(Appearance.imagesShadowColor)
        thumbnail.masksToBounds = false // let thumbnail shadows show
        thumbnail.applyShadow(thumbnailShadow)
        appIcon.applyShadow(appIconShadow)
        dockLabelIcon.shadow = shadow
        layer!.addSublayer(appIcon)
        addSubview(dockLabelIcon)
        label.fixHeight()
    }

    private func setupStyleSpecificSubviews() {
        if Preferences.appearanceStyle == .appIcons {
            addSubviews([label])
            setSubviewAbove(windowlessAppIndicator)
            label.alignment = .center
            label.isHidden = true
        } else if Preferences.appearanceStyle == .thumbnails {
            layer!.addSublayer(thumbnail)
            addSubviews([label, statusIcons])
            setSubviewAbove(windowlessAppIndicator)
        } else {
            setSubviewAbove(windowlessAppIndicator)
            addSubviews([label, statusIcons])
        }
    }

    private func updateAppIconsLabel(isFocused: Bool, isHovered: Bool) {
        let focusedView = TilesView.recycledViews[Windows.selectedWindowIndex]
        var hoveredView: TileView? = nil
        if Windows.hoveredWindowIndex != nil {
            hoveredView = TilesView.recycledViews[Windows.hoveredWindowIndex!]
        }
        if isFocused || (!isFocused && !isHovered) {
            hoveredView?.label.isHidden = true
            focusedView.label.isHidden = false
            focusedView.updateAppIconsLabelFrame()
        } else if isHovered {
            hoveredView?.label.isHidden = false
            focusedView.label.isHidden = true
            if let hoveredView {
                hoveredView.updateAppIconsLabelFrame()
            }
        }
    }

    private func getMaxAllowedLabelWidth() -> CGFloat {
        let viewWidth = frame.width
        let maxAllowedWidth = min(viewWidth * 2, TilesView.thumbnailsWidth)
        let availableLeftWidth = isFirstInRow ? 0 : CGFloat(indexInRow) * viewWidth
        let availableRightWidth = isLastInRow ? 0 : CGFloat(numberOfViewsInRow - 1 - indexInRow) * viewWidth
        let totalWidth = availableLeftWidth + availableRightWidth + viewWidth
        let maxLabelWidth = min(totalWidth, maxAllowedWidth)
        return maxLabelWidth - Appearance.intraCellPadding * 2
    }

    private func updateAppIconsLabelFrame() {
        let viewWidth = frame.width
        let labelWidth = fullTitleWidth
        let padding = (Preferences.appearanceSize == .small ? 0 : ( Preferences.appearanceSize == .medium ? 1 : 2)) * Appearance.intraCellPadding
        let maxAllowedLabelWidth = getMaxAllowedLabelWidth()
        let sidesToOffset: CGFloat = (isFirstInRow ? 1 : 0) + (isLastInRow ? 1 : 0)
        let paddingForOffset = sidesToOffset * padding
        var effectiveLabelWidth = max(min(labelWidth, maxAllowedLabelWidth), viewWidth) - paddingForOffset
        // if the label is small, and with an offset only on one side, we reduce its width to center its text
        if sidesToOffset == 1 && labelWidth <= (effectiveLabelWidth - paddingForOffset) {
            effectiveLabelWidth -= paddingForOffset
        }
        var leftOffset = CGFloat(0)
        if isFirstInRow {
            leftOffset = -padding
        } else if isLastInRow {
            leftOffset = effectiveLabelWidth - viewWidth + padding
        } else {
            let halfNeededOffset = max(0, (effectiveLabelWidth - viewWidth) / 2)
            let availableLeftWidth = isFirstInRow ? 0 : CGFloat(indexInRow) * viewWidth
            let availableRightWidth = isLastInRow ? 0 : CGFloat(numberOfViewsInRow - 1 - indexInRow) * viewWidth
            if availableLeftWidth >= halfNeededOffset && availableRightWidth >= halfNeededOffset {
                leftOffset = halfNeededOffset
            } else if availableLeftWidth <= halfNeededOffset && availableRightWidth <= halfNeededOffset {
                leftOffset = availableLeftWidth
            } else if availableRightWidth <= halfNeededOffset {
                leftOffset = min(effectiveLabelWidth - viewWidth - availableRightWidth, availableLeftWidth)
            } else if availableLeftWidth <= halfNeededOffset {
                leftOffset = availableLeftWidth
            }
        }
        let xPosition = -leftOffset
        let height = TilesView.layoutCache.labelHeight
        let yPosition = appIcon.frame.maxY + Appearance.intraCellPadding * 2
        label.frame = NSRect(x: xPosition, y: yPosition, width: effectiveLabelWidth, height: height)
        label.setWidth(effectiveLabelWidth)
        label.toolTip = labelWidth >= label.frame.size.width ? fullTitle : nil
        applySearchHighlight()
    }

    private func updateAppIcon(_ element: Window, _ title: String) {
        let appIconSize = TileView.iconSize()
        appIcon.updateContents(.cgImage(element.icon), appIconSize)
    }

    private func updateValues(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        assignIfDifferent(&windowlessAppIndicator.isHidden, !element.isWindowlessApp)
        statusIcons.update(
            isHidden: element.isHidden && !Preferences.hideStatusIcons,
            isFullscreen: element.isFullscreen && !Preferences.hideStatusIcons,
            isMinimized: element.isMinimized && !Preferences.hideStatusIcons,
            showSpace: !(element.isWindowlessApp || Spaces.isSingleSpace() || Preferences.hideSpaceNumberLabels || (
                Preferences.spacesToShow[App.app.shortcutIndex] == .visible && (
                    NSScreen.screens.count < 2 || Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab
                )
            ))
        )
        if !thumbnail.isHidden {
            if let screenshot = element.thumbnail {
                let thumbnailSize = TileView.thumbnailSize(element.size, false)
                thumbnail.updateContents(screenshot, thumbnailSize)
            } else {
                // if no thumbnail, show appIcon instead
                let thumbnailSize = TileView.thumbnailSize(element.icon?.size(), true)
                thumbnail.updateContents(.cgImage(element.icon), thumbnailSize)
            }
        }
        let title = getAppOrAndWindowTitle()
        let labelChanged = label.stringValue != title
        if labelChanged {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
        fullTitle = title
        fullTitleWidth = label.cell!.cellSize.width
        label.updateTruncationModeIfNeeded()
        if statusIcons.spaceVisible {
            let spaceIndex = element.spaceIndexes.first
            if element.isOnAllSpaces || (spaceIndex != nil && spaceIndex! > 30) {
                statusIcons.setSpaceStar()
            } else if let spaceIndex {
                statusIcons.setSpaceNumber(spaceIndex)
            }
        }
        updateAppIcon(element, title)
        updateDockLabelIcon(element.dockLabel)
        setAccessibilityHelp(getAccessibilityHelp(element.application.localizedName, element.dockLabel))
        mouseUpCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        mouseMovedCallback = { () -> Void in Windows.updateSelectedAndHoveredWindowIndex(index, true) }
    }

    private func applySearchHighlight() {
        let attributes = baseTitleAttributes()
        let query = Search.normalizedQuery(Windows.searchQuery)
        if query.isEmpty {
            label.attributedStringValue = NSAttributedString(string: fullTitle, attributes: attributes)
            return
        }
        let clippingAttributes = baseTitleAttributes(true)
        let spanRanges = searchSpanRanges()
        let titleLength = Array(fullTitle).count
        let highlightedIndexes = highlightedIndexes(spanRanges, titleLength)
        let truncation = truncatedDisplay(fullTitle, maxWidth: label.frame.size.width, mode: label.lineBreakMode, attributes: clippingAttributes)
        let attributed = NSMutableAttributedString(string: truncation.text, attributes: clippingAttributes)
        for range in visibleHighlightRanges(truncation.visibleToOriginal, highlightedIndexes) {
            attributed.addAttribute(TileTitleView.searchHighlightBackgroundKey, value: Appearance.searchMatchHighlightColor, range: range)
            attributed.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: range)
        }
        let visibleOriginalIndexes = Set(truncation.visibleToOriginal.compactMap { $0 })
        let hasHiddenHighlights = highlightedIndexes.contains { !visibleOriginalIndexes.contains($0) }
        if hasHiddenHighlights, let ellipsisIndex = truncation.ellipsisIndex {
            let range = NSRange(location: ellipsisIndex, length: 1)
            attributed.addAttribute(TileTitleView.searchHighlightBackgroundKey, value: Appearance.searchMatchHighlightColor, range: range)
            attributed.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: range)
        }
        label.attributedStringValue = attributed
    }

    private func baseTitleAttributes(_ forceClipping: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = label.alignment
        paragraphStyle.baseWritingDirection = .leftToRight
        paragraphStyle.lineBreakMode = forceClipping ? .byClipping : label.lineBreakMode
        return [.foregroundColor: Appearance.fontColor, .font: Appearance.font, .paragraphStyle: paragraphStyle]
    }

    private func searchSpanRanges() -> [NSRange] {
        var spanRanges = [NSRange]()
        if Preferences.onlyShowApplications() || Preferences.showTitles == .appName {
            for result in window_?.swAppResults ?? [] {
                spanRanges.append(NSRange(location: result.span.lowerBound, length: result.span.count))
            }
            return spanRanges
        }
        if Preferences.showTitles == .appNameAndWindowTitle {
            let appName = window_?.application.localizedName ?? ""
            let offset = appName.isEmpty ? 0 : (appName + " - ").count
            for result in window_?.swAppResults ?? [] {
                spanRanges.append(NSRange(location: result.span.lowerBound, length: result.span.count))
            }
            for result in window_?.swTitleResults ?? [] {
                spanRanges.append(NSRange(location: offset + result.span.lowerBound, length: result.span.count))
            }
            return spanRanges
        }
        for result in window_?.swTitleResults ?? [] {
            spanRanges.append(NSRange(location: result.span.lowerBound, length: result.span.count))
        }
        return spanRanges
    }

    private func highlightedIndexes(_ ranges: [NSRange], _ titleLength: Int) -> Set<Int> {
        var indexes = Set<Int>()
        for range in ranges {
            if range.length <= 0 { continue }
            let start = max(0, range.location)
            let end = min(titleLength, start + range.length)
            if start >= end { continue }
            for index in start..<end {
                indexes.insert(index)
            }
        }
        return indexes
    }

    private func visibleHighlightRanges(_ visibleToOriginal: [Int?], _ highlightedIndexes: Set<Int>) -> [NSRange] {
        var ranges = [NSRange]()
        var runStart: Int?
        for (displayIndex, originalIndex) in visibleToOriginal.enumerated() {
            let highlighted = originalIndex.flatMap { highlightedIndexes.contains($0) } ?? false
            if highlighted {
                if runStart == nil {
                    runStart = displayIndex
                }
            } else if let runStartValue = runStart {
                ranges.append(NSRange(location: runStartValue, length: displayIndex - runStartValue))
                runStart = nil
            }
        }
        if let runStart {
            ranges.append(NSRange(location: runStart, length: visibleToOriginal.count - runStart))
        }
        return ranges
    }

    private func truncatedDisplay(_ title: String, maxWidth: CGFloat, mode: NSLineBreakMode, attributes: [NSAttributedString.Key: Any]) -> (text: String, visibleToOriginal: [Int?], ellipsisIndex: Int?) {
        let chars = Array(title)
        if chars.isEmpty { return ("", [], nil) }
        if maxWidth <= 0 { return ("", [], nil) }
        if measuredWidth(title, attributes) <= maxWidth {
            return (title, Array(0..<chars.count).map { Optional($0) }, nil)
        }
        let ellipsis = "…"
        if measuredWidth(ellipsis, attributes) > maxWidth {
            return (ellipsis, [nil], 0)
        }
        if mode == .byTruncatingHead {
            var low = 0
            var high = chars.count
            while low < high {
                let mid = (low + high + 1) / 2
                let candidate = ellipsis + String(chars.suffix(mid))
                if measuredWidth(candidate, attributes) <= maxWidth {
                    low = mid
                } else {
                    high = mid - 1
                }
            }
            let suffixCount = low
            let suffixStart = chars.count - suffixCount
            let text = ellipsis + String(chars.suffix(suffixCount))
            let mapping = [Int?](arrayLiteral: nil) + Array(suffixStart..<chars.count).map { Optional($0) }
            return (text, mapping, 0)
        }
        if mode == .byTruncatingMiddle {
            var leftCount = (chars.count + 1) / 2
            var rightStart = leftCount
            var candidate = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
            while measuredWidth(candidate, attributes) > maxWidth && (leftCount > 0 || rightStart < chars.count) {
                if rightStart < chars.count {
                    rightStart += 1
                }
                candidate = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
                if measuredWidth(candidate, attributes) <= maxWidth {
                    break
                }
                if leftCount > 0 {
                    leftCount -= 1
                }
                candidate = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
            }
            if measuredWidth(candidate, attributes) > maxWidth {
                return (ellipsis, [nil], 0)
            }
            let text = String(chars.prefix(leftCount)) + ellipsis + String(chars.suffix(chars.count - rightStart))
            let mapping = Array(0..<leftCount).map { Optional($0) } + [nil] + Array(rightStart..<chars.count).map { Optional($0) }
            return (text, mapping, leftCount)
        }
        var low = 0
        var high = chars.count
        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(chars.prefix(mid)) + ellipsis
            if measuredWidth(candidate, attributes) <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let prefixCount = low
        let text = String(chars.prefix(prefixCount)) + ellipsis
        let mapping = Array(0..<prefixCount).map { Optional($0) } + [nil]
        return (text, mapping, prefixCount)
    }

    private func measuredWidth(_ text: String, _ attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        (text as NSString).size(withAttributes: attributes).width
    }

    private func updateSizes(_ newHeight: CGFloat) {
        setFrameWidthHeight(newHeight)
        if Preferences.appearanceStyle != .appIcons {
            let hWidth = frame.width - Appearance.edgeInsetsSize * 2
            let labelWidth = hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - statusIcons.totalWidth
            label.setWidth(labelWidth)
        }
    }

    private func updatePositions(_ newHeight: CGFloat) {
        let edgeInsets = Appearance.edgeInsetsSize
        assignIfDifferent(&appIcon.frame.origin, NSPoint(x: edgeInsets, y: edgeInsets))
        if Preferences.appearanceStyle != .appIcons {
            let hWidth = frame.width - edgeInsets * 2
            let hHeight = max(appIcon.frame.height, TilesView.layoutCache.labelHeight)
            if App.shared.userInterfaceLayoutDirection == .rightToLeft {
                assignIfDifferent(&appIcon.frame.origin.x, edgeInsets + hWidth - appIcon.frame.width)
            }
            statusIcons.layoutIcons(hWidth: hWidth, hHeight: hHeight, edgeInsets: edgeInsets)
            let labelWidth = hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - statusIcons.totalWidth
            let labelX: CGFloat
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                labelX = appIcon.frame.maxX + Appearance.appIconLabelSpacing
            } else {
                labelX = edgeInsets + hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - labelWidth
            }
            assignIfDifferent(&label.frame.origin.x, labelX)
            assignIfDifferent(&label.frame.origin.y, edgeInsets + ((hHeight - TilesView.layoutCache.labelHeight) / 2).rounded())
        }
        if Preferences.appearanceStyle == .thumbnails {
            let hHeight = max(appIcon.frame.height, TilesView.layoutCache.labelHeight)
            assignIfDifferent(&thumbnail.frame.origin, NSPoint(x: edgeInsets, y: edgeInsets + hHeight + Appearance.intraCellPadding))
            thumbnail.centerInSuperlayer(x: true)
        }
        updateWindowlessAppIndicatorPosition()
        updateDockLabelIconPosition()
    }

    private func updateDockLabelIconPosition() {
        let iconSize = max(appIcon.frame.width, appIcon.frame.height)
        let offset = (iconSize * (Preferences.appearanceStyle == .appIcons && Preferences.appearanceSize == .large ? 0.03 : 0.05)).rounded()
        let badgeTopRightX = appIcon.frame.maxX + offset
        let badgeTopRightY = appIcon.frame.minY - offset
        assignIfDifferent(&dockLabelIcon.frame.origin.x, badgeTopRightX - dockLabelIcon.frame.width)
        assignIfDifferent(&dockLabelIcon.frame.origin.y, badgeTopRightY)
    }

    private func updateWindowlessAppIndicatorPosition() {
        guard !windowlessAppIndicator.isHidden else { return }
        assignIfDifferent(&windowlessAppIndicator.frame.origin.x, windowlessIndicatorXPosition())
        assignIfDifferent(&windowlessAppIndicator.frame.origin.y, windowlessIndicatorYPosition())
    }

    private func windowlessIndicatorXPosition() -> CGFloat {
        if Preferences.appearanceStyle == .thumbnails {
            return thumbnail.frame.origin.x + ((thumbnail.frame.width - windowlessAppIndicator.frame.width) / 2).rounded()
        }
        return (appIcon.frame.midX - windowlessAppIndicator.frame.width / 2).rounded()
    }

    private func windowlessIndicatorYPosition() -> CGFloat {
        let verticalOffset = Preferences.appearanceStyle == .titles ? CGFloat(5) : CGFloat(10)
        if Preferences.appearanceStyle == .thumbnails {
            return (thumbnail.frame.maxY - windowlessAppIndicator.frame.height + verticalOffset).rounded()
        }
        return (appIcon.frame.maxY - windowlessAppIndicator.frame.height + verticalOffset).rounded()
    }

    private func getAppOrAndWindowTitle() -> String {
        let appName = window_?.application.localizedName
        let windowTitle = window_?.title
        if Preferences.onlyShowApplications() || Preferences.showTitles == .appName {
            return appName ?? ""
        } else if Preferences.showTitles == .appNameAndWindowTitle {
            return [appName, windowTitle].compactMap { $0 }.joined(separator: " - ")
        }
        return windowTitle ?? ""
    }

    private func setFrameWidthHeight(_ newHeight: CGFloat) {
        var contentWidth = CGFloat(0)
        if Preferences.appearanceStyle == .thumbnails {
            // Preferred to the width of the image, and the minimum width may be set to be large.
            contentWidth = thumbnail.frame.size.width
        } else if Preferences.appearanceStyle == .titles {
            contentWidth = TileView.maxThumbnailWidth() - Appearance.edgeInsetsSize * 2
        } else {
            contentWidth = Appearance.iconSize
        }
        let frameWidth = (contentWidth + Appearance.edgeInsetsSize * 2).rounded()
        let widthMin = TileView.minThumbnailWidth()
        let width = max(frameWidth, widthMin).rounded()
        assignIfDifferent(&frame.size.width, width)
        assignIfDifferent(&frame.size.height, newHeight)
    }

    private func getAccessibilityHelp(_ appName: String?, _ dockLabel: String?) -> String {
        [appName, dockLabel.map { getAccessibilityTextForBadge($0) }]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func getAccessibilityTextForBadge(_ dockLabel: String) -> String {
        if let dockLabelInt = Int(dockLabel) {
            return "Red badge with number \(dockLabelInt)"
        }
        return "Red badge"
    }

    private func observeDragAndDrop() {
        // we only handle URLs (i.e. not text, image, or other draggable things)
        registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeURL as String)])
    }

    static func makeShadow(_ color: NSColor?) -> NSShadow? {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    static func makeAppIconShadow(_ color: NSColor?) -> NSShadow? {
        guard let color else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 0.1, height: 1)
        shadow.shadowBlurRadius = 2
        return shadow
    }

    static func makeThumbnailShadow(_ color: NSColor?) -> NSShadow? {
        guard let color else { return nil }
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.4)
        shadow.shadowOffset = NSSize(width: 0.8, height: 2.2)
        shadow.shadowBlurRadius = 3
        return shadow
    }

    static func maxThumbnailWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return TilesPanel.maxThumbnailsWidth(screen) * Appearance.windowMaxWidthInRow - Appearance.interCellPadding * 2
    }

    static func widthOfComfortableReadability() -> CGFloat? {
        let labTitleView = TileTitleView(font: Appearance.font)
        labTitleView.stringValue = "abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz" + extraTextForPadding
        return labTitleView.cell!.cellSize.width
    }

    static func widthOfLongestTitle() -> CGFloat? {
        let labTitleView = TileTitleView(font: Appearance.font)
        var maxWidth = CGFloat(0)
        for window in Windows.list {
            guard window.shouldShowTheUser else { continue }
            labTitleView.stringValue = window.title + extraTextForPadding
            let width = labTitleView.cell!.cellSize.width
            if width > maxWidth {
                maxWidth = width
            }
        }
        guard maxWidth > 0 else { return nil }
        return maxWidth
    }

    static func minThumbnailWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return TilesPanel.maxThumbnailsWidth(screen) * Appearance.windowMinWidthInRow - Appearance.interCellPadding * 2
    }

    /// The maximum height that a thumbnail can be drawn
    /// maxThumbnailsHeight = maxThumbnailHeight * rowCount + interCellPadding * (rowCount - 1)
    /// maxThumbnailHeight = (maxThumbnailsHeight - interCellPadding * (rowCount - 1)) / rowCount
    static func maxThumbnailHeight(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return ((TilesPanel.maxThumbnailsHeight(screen) - Appearance.interCellPadding) / Appearance.rowsCount - Appearance.interCellPadding).rounded()
    }

    static func thumbnailSize(_ imageSize: NSSize?, _ isWindowlessApp: Bool) -> NSSize {
        guard let imageSize else { return NSSize(width: 0, height: 0) }
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height
        let thumbnailHeightMax = TileView.maxThumbnailHeight()
            - Appearance.edgeInsetsSize * 2
            - Appearance.intraCellPadding
            - Appearance.iconSize
        let thumbnailWidthMax = TileView.maxThumbnailWidth()
            - Appearance.edgeInsetsSize * 2
        // don't stretch very small windows; keep them 1:1 in the switcher
        if !isWindowlessApp && imageWidth < thumbnailWidthMax && imageHeight < thumbnailHeightMax {
            return imageSize
        }
        let thumbnailHeight = min(imageHeight, thumbnailHeightMax)
        let thumbnailWidth = min(imageWidth, thumbnailWidthMax)
        let imageRatio = imageWidth / imageHeight
        let thumbnailRatio = thumbnailWidth / thumbnailHeight
        var width: CGFloat
        var height: CGFloat
        if thumbnailRatio > imageRatio {
            // Keep the height and reduce the width
            width = imageWidth * thumbnailHeight / imageHeight
            height = thumbnailHeight
        } else if thumbnailRatio < imageRatio {
            // Keep the width and reduce the height
            width = thumbnailWidth
            height = imageHeight * thumbnailWidth / imageWidth
        } else {
            // Enlarge the height to the maximum height and enlarge the width
            width = thumbnailHeightMax / imageHeight * imageWidth
            height = thumbnailHeightMax
        }
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    static func iconSize(_ screen: NSScreen = NSScreen.preferred) -> NSSize {
        if Preferences.appearanceStyle == .appIcons {
            let widthMin = TileView.minThumbnailWidth(screen)
            let contentWidth = Appearance.iconSize
            let frameWidth = contentWidth + Appearance.edgeInsetsSize * 2
            let width = max(frameWidth, widthMin).rounded()
            if widthMin > frameWidth {
                let iconSize = width - Appearance.edgeInsetsSize * 2
                return NSSize(width: iconSize, height: iconSize)
            }
        }
        return NSSize(width: Appearance.iconSize, height: Appearance.iconSize)
    }

    static func height(_ labelHeight: CGFloat) -> CGFloat {
        if Preferences.appearanceStyle == .titles {
            return max(TileView.iconSize().height, labelHeight) + Appearance.edgeInsetsSize * 2
        } else if Preferences.appearanceStyle == .appIcons {
            return TileView.iconSize().height + Appearance.edgeInsetsSize * 2 + Appearance.intraCellPadding * 2 + labelHeight
        }
        return TileView.maxThumbnailHeight()
    }
}
