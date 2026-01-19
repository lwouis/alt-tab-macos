import Cocoa

class ThumbnailsView {
    var scrollView: ScrollView!
    var contentView: EffectView!
    var rows = [[ThumbnailView]]()
    private var searchField = SearchFieldView()
    private let searchFieldVerticalPadding = CGFloat(10)
    private let searchFieldHorizontalInset = CGFloat(12)
    static var recycledViews = [ThumbnailView]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)

    init() {
        updateBackgroundView()
        // TODO: think about this optimization more
        (1...20).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
    }

    func updateBackgroundView() {
        contentView = makeAppropriateEffectView()
        scrollView = ScrollView()
        contentView.addSubview(scrollView)
        setupSearchField()
    }

    private func setupSearchField() {
        searchField = SearchFieldView()
        contentView.addSubview(searchField)
    }

    private func updateSearchField() {
        let isActivationRequired = Windows.requiresSearchActivation && !Windows.isSearchModeActive
        let placeholder = isActivationRequired
            ? NSLocalizedString("Press S to filter", comment: "")
            : NSLocalizedString("Type to filter", comment: "")
        let isActive = Windows.isSearchModeActive || !Windows.requiresSearchActivation
        searchField.update(text: Windows.searchQueryDisplayText, placeholder: placeholder, isActive: isActive)
    }

    private func searchFieldTopPadding() -> CGFloat {
        let basePadding = Appearance.windowPadding
        let areaHeight = searchField.preferredHeight + searchFieldVerticalPadding * 2
        return max(basePadding, areaHeight)
    }

    private func adjustedMaxXForSearchField(_ maxX: CGFloat, _ widthMax: CGFloat) -> CGFloat {
        let maxWidth = max(widthMax - searchFieldHorizontalInset * 2, 0)
        let fieldWidth = searchField.desiredWidth(maxWidth: maxWidth) + searchFieldHorizontalInset * 2
        return max(maxX, fieldWidth)
    }

    private func layoutSearchField(_ originX: CGFloat, _ availableWidth: CGFloat, _ topPadding: CGFloat) {
        let fieldHeight = searchField.preferredHeight
        let offset = max((topPadding - fieldHeight) / 2, 0)
        let y = contentView.frame.height - topPadding + offset
        let maxWidth = max(availableWidth - searchFieldHorizontalInset * 2, 0)
        let fieldWidth = searchField.desiredWidth(maxWidth: maxWidth)
        let x = originX + searchFieldHorizontalInset
        searchField.frame = NSRect(x: x, y: y, width: fieldWidth, height: fieldHeight)
    }

    func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        NSScreen.updatePreferred()
        Appearance.update()
        // thumbnails are captured continuously. They will pick up the new size on the next cycle
        ThumbnailsPanel.updateMaxPossibleThumbnailSize()
        // app icons are captured once at launch; we need to manually update them if needed
        let old = ThumbnailsPanel.maxPossibleAppIconSize.width
        ThumbnailsPanel.updateMaxPossibleAppIconSize()
        if old != ThumbnailsPanel.maxPossibleAppIconSize.width {
            Applications.updateAppIcons()
        }
        updateBackgroundView()
        App.app.thumbnailsPanel.contentView = contentView
        for i in 0..<ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews[i] = ThumbnailView()
        }
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        if view.frame != NSRect.zero {
            view.drawHighlight()
        }
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [ThumbnailView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.focusedWindow()?.rowIndex {
            var nextRow = currentRow + step
            if nextRow >= rows.count {
                if allowWrap {
                    nextRow = nextRow % rows.count
                } else {
                    return nil
                }
            } else if nextRow < 0 {
                if allowWrap {
                    nextRow = rows.count + nextRow
                } else {
                    return nil
                }
            }
            if ((step > 0 && nextRow < currentRow) || (step < 0 && nextRow > currentRow)) &&
                   (ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended) {
                return nil
            }
            return rows[nextRow]
        }
        return nil
    }

    func navigateUpOrDown(_ direction: Direction, allowWrap: Bool = true) {
        guard Windows.focusedWindowIndex < ThumbnailsView.recycledViews.count else { return }
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.focusedWindowIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        guard let targetRow = nextRow(direction, allowWrap: allowWrap), !targetRow.isEmpty else { return }
        let leftSide = originCenter < NSMidX(contentView.frame)
        let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
        let iterable = leadingSide ? targetRow : targetRow.reversed()
        guard let targetView = iterable.first(where: {
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
            }
            return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
        }) ?? iterable.last else { return }
        guard let targetIndex = ThumbnailsView.recycledViews.firstIndex(of: targetView) else { return }
        Windows.updateFocusedAndHoveredWindowIndex(targetIndex)
    }

    func updateItemsAndLayout() {
        updateSearchField()
        let widthMax = ThumbnailsPanel.maxThumbnailsWidth().rounded()
        if let (maxX, maxY, labelHeight) = layoutThumbnailViews(widthMax) {
            let adjustedMaxX = adjustedMaxXForSearchField(maxX, widthMax)
            layoutParentViews(adjustedMaxX, widthMax, maxY, labelHeight)
            if Preferences.alignThumbnails == .center {
                centerRows(adjustedMaxX)
            }
            for row in rows {
                for (j, view) in row.enumerated() {
                    view.numberOfViewsInRow = row.count
                    view.isFirstInRow = j == 0
                    view.isLastInRow = j == row.count - 1
                    view.indexInRow = j
                }
            }
            highlightStartView()
        }
    }

    private func layoutThumbnailViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat)? {
        let labelHeight = ThumbnailsView.recycledViews.first!.label.fittingSize.height
        let height = ThumbnailView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [ThumbnailView]()
        rows.removeAll(keepingCapacity: true)
        rows.append([ThumbnailView]())
        var index = 0
        while index < ThumbnailsView.recycledViews.count {
            guard App.app.appIsBeingUsed else { return nil }
            defer { index = index + 1 }
            let view = ThumbnailsView.recycledViews[index]
            if index < Windows.list.count {
                let window = Windows.list[index]
                guard window.shouldShowTheUser else { continue }
                view.updateRecycledCellWithNewContent(window, index, height)
                let width = view.frame.size.width
                let projectedX = projectedWidth(currentX, width).rounded(.down)
                if needNewLine(projectedX, widthMax) {
                    currentX = startingX
                    currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedWidth(currentX, width).rounded(.down)
                    maxY = max(currentY + height + Appearance.interCellPadding, maxY)
                    rows.append([ThumbnailView]())
                } else {
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedX
                    maxX = max(isLeftToRight ? currentX : widthMax - currentX, maxX)
                }
                rows[rows.count - 1].append(view)
                newViews.append(view)
                window.rowIndex = rows.count - 1
            } else {
                // release images from unused recycledViews; they take lots of RAM
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
            }
        }
        scrollView.documentView!.subviews = newViews
        return (maxX, maxY, labelHeight)
    }

    private func needNewLine(_ projectedX: CGFloat, _ widthMax: CGFloat) -> Bool {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return projectedX > widthMax
        }
        return projectedX < 0
    }

    private func projectedWidth(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return currentX + width + Appearance.interCellPadding
        }
        return currentX - width - Appearance.interCellPadding
    }

    private func localizedCurrentX(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX : currentX - width
    }

    private func layoutParentViews(_ maxX: CGFloat, _ widthMax: CGFloat, _ maxY: CGFloat, _ labelHeight: CGFloat) {
        let basePadding = Appearance.windowPadding
        let topPadding = searchFieldTopPadding()
        let extraTopPadding = max(0, topPadding - basePadding)
        let heightMax = max(ThumbnailsPanel.maxThumbnailsHeight() - extraTopPadding, 0)
        ThumbnailsView.thumbnailsWidth = min(maxX, widthMax)
        ThumbnailsView.thumbnailsHeight = min(maxY, heightMax)
        let frameWidth = ThumbnailsView.thumbnailsWidth + basePadding * 2
        var frameHeight = ThumbnailsView.thumbnailsHeight + basePadding + topPadding
        let originX = basePadding
        var originY = basePadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: ThumbnailsView.thumbnailsHeight)
        scrollView.frame.origin = CGPoint(x: originX, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        layoutSearchField(originX, ThumbnailsView.thumbnailsWidth, topPadding)
        if let existingTrackingArea = scrollView.trackingAreas.first {
            scrollView.removeTrackingArea(existingTrackingArea)
        }
        scrollView.addTrackingArea(NSTrackingArea(rect: scrollView.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: scrollView, userInfo: nil))
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = Appearance.interCellPadding
        var rowY = Appearance.interCellPadding
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            if view.frame.origin.y == rowY {
                rowWidth += view.frame.size.width + Appearance.interCellPadding
            } else {
                shiftRow(maxX, rowWidth, rowStartIndex, index)
                rowStartIndex = index
                rowWidth = Appearance.interCellPadding + view.frame.size.width + Appearance.interCellPadding
                rowY = view.frame.origin.y
            }
        }
        shiftRow(maxX, rowWidth, rowStartIndex, Windows.list.count)
    }

    private func highlightStartView() {
        ThumbnailsView.highlight(Windows.focusedWindowIndex)
        if let hoveredWindowIndex = Windows.hoveredWindowIndex {
            ThumbnailsView.highlight(hoveredWindowIndex)
        }
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            for i in rowStartIndex..<index {
                ThumbnailsView.recycledViews[i].frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
            }
        }
    }
}

class SearchFieldView: NSView {
    private let iconView = NSImageView()
    private let textLabel = TextField("")
    private let placeholderLabel = TextField("")
    private let horizontalPadding = CGFloat(10)
    private let iconSpacing = CGFloat(6)
    private let minWidth = CGFloat(160)
    private let minHeight = CGFloat(22)

    var preferredHeight: CGFloat {
        max(minHeight, Appearance.fontHeight + 12)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        iconView.imageScaling = .scaleProportionallyDown
        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
                iconView.image = image
            } else {
                iconView.isHidden = true
            }
        } else {
            iconView.isHidden = true
        }
        textLabel.usesSingleLineMode = true
        textLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.usesSingleLineMode = true
        placeholderLabel.lineBreakMode = .byTruncatingTail
        addSubview(iconView)
        addSubview(placeholderLabel)
        addSubview(textLabel)
    }

    func update(text: String, placeholder: String, isActive: Bool) {
        textLabel.stringValue = text
        placeholderLabel.stringValue = placeholder
        let hasText = !text.isEmpty
        textLabel.isHidden = !hasText
        placeholderLabel.isHidden = hasText
        updateAppearance(isActive: isActive)
        needsLayout = true
    }

    func desiredWidth(maxWidth: CGFloat) -> CGFloat {
        let textWidth = max(textLabel.fittingSize.width, placeholderLabel.fittingSize.width)
        let iconWidth = iconSize(for: preferredHeight).width
        let effectiveIconWidth = iconView.isHidden ? 0 : iconWidth + iconSpacing
        let width = horizontalPadding * 2 + effectiveIconWidth + textWidth
        return min(maxWidth, max(width, minWidth))
    }

    override func layout() {
        super.layout()
        let iconSize = iconSize(for: bounds.height)
        let iconWidth = iconView.isHidden ? 0 : iconSize.width
        let contentStartX = horizontalPadding + (iconWidth > 0 ? iconWidth + iconSpacing : 0)
        let textWidth = max(bounds.width - contentStartX - horizontalPadding, 0)
        let textHeight = max(textLabel.fittingSize.height, placeholderLabel.fittingSize.height)
        let textY = max((bounds.height - textHeight) / 2, 0)
        textLabel.frame = NSRect(x: contentStartX, y: textY, width: textWidth, height: textHeight)
        placeholderLabel.frame = textLabel.frame
        if iconWidth > 0 {
            let iconY = max((bounds.height - iconSize.height) / 2, 0)
            iconView.frame = NSRect(x: horizontalPadding, y: iconY, width: iconSize.width, height: iconSize.height)
        } else {
            iconView.frame = .zero
        }
        layer?.cornerRadius = bounds.height / 2
    }

    private func updateAppearance(isActive: Bool) {
        let backgroundColor = Appearance.currentTheme == .dark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06)
        let borderColor = isActive
            ? NSColor.systemAccentColor.withAlphaComponent(0.6)
            : Appearance.fontColor.withAlphaComponent(0.25)
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = borderColor.cgColor
        let shadowColor = Appearance.currentTheme == .dark
            ? NSColor.black.withAlphaComponent(0.6)
            : NSColor.black.withAlphaComponent(0.2)
        layer?.shadowColor = shadowColor.cgColor
        layer?.shadowOpacity = isActive ? 0.18 : 0.12
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        let alignment: NSTextAlignment = App.shared.userInterfaceLayoutDirection == .leftToRight ? .left : .right
        textLabel.font = Appearance.font
        textLabel.textColor = Appearance.fontColor
        textLabel.alignment = alignment
        placeholderLabel.font = Appearance.font
        placeholderLabel.textColor = Appearance.fontColor.withAlphaComponent(0.45)
        placeholderLabel.alignment = alignment
        if #available(macOS 10.14, *) {
            iconView.contentTintColor = Appearance.fontColor.withAlphaComponent(0.6)
        }
    }

    private func iconSize(for height: CGFloat) -> NSSize {
        let size = max(min(height - 6, Appearance.fontHeight + 2), 0)
        return NSSize(width: size, height: size)
    }
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    var isCurrentlyScrolling = false
    var previousTarget: ThumbnailView?

    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        verticalScrollElasticity = .none
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        observeScrollingEvents()
    }

    private func observeScrollingEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingStarted), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingEnded), name: NSScrollView.didEndLiveScrollNotification, object: nil)
    }

    @objc private func scrollingStarted() {
        isCurrentlyScrolling = true
    }

    @objc private func scrollingEnded() {
        isCurrentlyScrolling = false
    }

    private func resetHoveredWindow() {
        if let oldIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
            ThumbnailsView.recycledViews[oldIndex].showOrHideWindowControls(false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        previousTarget = nil
        resetHoveredWindow()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let documentView, !isCurrentlyScrolling && CursorEvents.isAllowedToMouseHover else { return }
        let location = documentView.convert(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream, from: nil)
        let newTarget = findTarget(location)
        guard newTarget !== previousTarget else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let newTarget {
            previousTarget?.showOrHideWindowControls(false)
            newTarget.mouseMoved()
        } else {
            resetHoveredWindow()
        }
        previousTarget = newTarget
        CATransaction.commit()
    }

    private func findTarget(_ location: NSPoint) -> ThumbnailView? {
        for case let view as ThumbnailView in documentView!.subviews {
            let frame = view.frame
            let expandedFrame = CGRect(x: frame.minX - (App.shared.userInterfaceLayoutDirection == .leftToRight ? 0 : 1), y: frame.minY, width: frame.width + 1, height: frame.height + 1)
            if expandedFrame.contains(location) {
                return view
            }
        }
        return nil
    }

    /// Checks whether the mouse pointer is within the padding area around a thumbnail.
    ///
    /// This is used to avoid gaps between thumbnail views where the mouse pointer might not be detected.
    ///
    /// @return `true` if the mouse pointer is within the padding area around a thumbnail; `false` otherwise.
    private func checkIfWithinInterPadding() -> Bool {
        if Preferences.appearanceStyle == .appIcons {
            let mouseLocation = App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream
            let mouseRect = NSRect(x: mouseLocation.x - Appearance.interCellPadding,
                y: mouseLocation.y - Appearance.interCellPadding,
                width: 2 * Appearance.interCellPadding,
                height: 2 * Appearance.interCellPadding)
            if let hoveredWindowIndex = Windows.hoveredWindowIndex {
                let thumbnail = ThumbnailsView.recycledViews[hoveredWindowIndex]
                let mouseRectInView = thumbnail.convert(mouseRect, from: nil)
                if thumbnail.bounds.intersects(mouseRectInView) {
                    return true
                }
            }
        }
        return false
    }

    /// holding shift and using the scrolling wheel will generate a horizontal movement
    /// shift can be part of shortcuts so we force shift scrolls to be vertical
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) && event.scrollingDeltaY == 0 {
            let cgEvent = event.cgEvent!
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 0)
            super.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

enum Direction {
    case right
    case left
    case leading
    case trailing
    case up
    case down

    func step() -> Int {
        if self == .left {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? -1 : 1
        } else if self == .right {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? 1 : -1
        }
        return self == .leading ? 1 : -1
    }
}
