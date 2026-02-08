import Cocoa

class ThumbnailsView {
    var scrollView: ScrollView!
    var contentView: EffectView!
    var rows = [[ThumbnailView]]()
    private var lastRowSignature = [Int]()
    static var recycledViews = [ThumbnailView]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)
    static var layoutCache = LayoutCache()
    var highlightOverlay = HighlightOverlayView()

    init() {
        updateBackgroundView()
        // TODO: think about this optimization more
        (1...20).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
        Self.updateCachedSizes()
    }

    static func updateCachedSizes() {
        guard let firstView = ThumbnailsView.recycledViews.first else { return }
        layoutCache.labelHeight = firstView.label.cell!.cellSize.height
        let iconCellSize = firstView.statusIcons.iconCellSize
        layoutCache.iconWidth = iconCellSize.width
        layoutCache.iconHeight = iconCellSize.height
        layoutCache.dockLabelSize = firstView.dockLabelIcon.frame.size
        layoutCache.comfortableReadabilityWidth = ThumbnailView.widthOfComfortableReadability()
    }

    func updateBackgroundView() {
        contentView = makeAppropriateEffectView()
        scrollView = ScrollView()
        contentView.addSubview(scrollView)
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
        highlightOverlay = HighlightOverlayView()
        Self.updateCachedSizes()
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        guard view.frame != .zero else { return }
        view.drawHighlight()
        let overlay = App.app.thumbnailsPanel.thumbnailsView.highlightOverlay
        let focusedView = recycledViews[Windows.selectedWindowIndex]
        let hoveredView = Windows.hoveredWindowIndex.map { recycledViews[$0] }
        overlay.updateHighlight(
            focusedView: focusedView.frame != .zero ? focusedView : nil,
            hoveredView: hoveredView != focusedView && hoveredView?.frame != .zero ? hoveredView : nil
        )
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [ThumbnailView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.selectedWindow()?.rowIndex {
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
        guard Windows.selectedWindowIndex < ThumbnailsView.recycledViews.count else { return }
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.selectedWindowIndex].frame
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
        Windows.updateSelectedAndHoveredWindowIndex(targetIndex)
    }

    func updateItemsAndLayout() {
        let widthMax = ThumbnailsPanel.maxThumbnailsWidth().rounded()
        if let (maxX, maxY, labelHeight, rowSignature) = layoutThumbnailViews(widthMax) {
            layoutParentViews(maxX, widthMax, maxY, labelHeight)
            if Preferences.alignThumbnails == .center {
                centerRows(maxX)
            }
            if rowSignature != lastRowSignature {
                for row in rows {
                    for (j, view) in row.enumerated() {
                        view.numberOfViewsInRow = row.count
                        view.isFirstInRow = j == 0
                        view.isLastInRow = j == row.count - 1
                        view.indexInRow = j
                    }
                }
                lastRowSignature = rowSignature
            }
            highlightStartView()
        }
    }

    private func layoutThumbnailViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat, [Int])? {
        let labelHeight = Self.layoutCache.labelHeight
        let height = ThumbnailView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [ThumbnailView]()
        var rowSignature = [Int]()
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
                rowSignature.append(index)
                window.rowIndex = rows.count - 1
            } else {
                // release images from unused recycledViews; they take lots of RAM
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
            }
        }
        scrollView.documentView!.subviews = newViews
        scrollView.documentView!.addSubview(highlightOverlay)
        return (maxX, maxY, labelHeight, rowSignature)
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
        let heightMax = ThumbnailsPanel.maxThumbnailsHeight()
        ThumbnailsView.thumbnailsWidth = min(maxX, widthMax)
        ThumbnailsView.thumbnailsHeight = min(maxY, heightMax)
        let frameWidth = ThumbnailsView.thumbnailsWidth + Appearance.windowPadding * 2
        var frameHeight = ThumbnailsView.thumbnailsHeight + Appearance.windowPadding * 2
        let originX = Appearance.windowPadding
        var originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: min(maxY, heightMax))
        scrollView.frame.origin = CGPoint(x: originX, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        highlightOverlay.frame = CGRect(origin: .zero, size: scrollView.documentView!.frame.size)
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
        ThumbnailsView.highlight(Windows.selectedWindowIndex)
        if let hoveredWindowIndex = Windows.hoveredWindowIndex {
            ThumbnailsView.highlight(hoveredWindowIndex)
            if highlightOverlay.isShowingWindowControls {
                highlightOverlay.showWindowControls(for: ThumbnailsView.recycledViews[hoveredWindowIndex])
            }
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

    func clearNeedsLayout() {
        let views = [contentView, scrollView, scrollView.contentView, scrollView.documentView].compactMap { $0 }
        for view in views {
            view.needsLayout = false
            view.needsDisplay = false
            view.needsUpdateConstraints = false
        }
    }

    struct LayoutCache {
        var labelHeight = CGFloat(0)
        var iconWidth = CGFloat(0)
        var iconHeight = CGFloat(0)
        var dockLabelSize = NSSize.zero
        var comfortableReadabilityWidth: CGFloat?
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
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
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
        }
        App.app.thumbnailsPanel.thumbnailsView.highlightOverlay.hideWindowControls()
    }

    override func mouseExited(with event: NSEvent) {
        caTransaction {
            previousTarget = nil
            resetHoveredWindow()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let documentView, !isCurrentlyScrolling && CursorEvents.isAllowedToMouseHover else { return }
        let location = documentView.convert(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream, from: nil)
        let newTarget = findTarget(location)
        guard newTarget !== previousTarget else { return }
        let overlay = App.app.thumbnailsPanel.thumbnailsView.highlightOverlay
        caTransaction {
            if let newTarget {
                overlay.hideWindowControls()
                newTarget.mouseMoved()
                overlay.showWindowControls(for: newTarget)
            } else {
                resetHoveredWindow()
            }
            previousTarget = newTarget
        }
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
    // Prevent AppKit from recursively marking all NSControl subviews as needsDisplay during makeKeyAndOrderFront
    // Titles, Icons, and Traffic Icons would otherwise take lots of resource to update
    // We update everything explicitly, so this can be disabled
    @objc func _windowChangedKeyState() {}
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
