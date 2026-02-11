import Cocoa

class TilesView {
    var scrollView: ScrollView!
    var contentView: EffectView!
    var rows = [[TileView]]()
    private var lastRowSignature = [Int]()
    static var recycledViews = [TileView]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)
    static var layoutCache = LayoutCache()
    var thumbnailUnderLayer = TileUnderLayer()
    var thumbnailOverView = TileOverView()

    init() {
        updateBackgroundView()
        // TODO: think about this optimization more
        (1...20).forEach { _ in TilesView.recycledViews.append(TileView()) }
        Self.updateCachedSizes()
    }

    static func updateCachedSizes() {
        guard let firstView = TilesView.recycledViews.first else { return }
        layoutCache.labelHeight = firstView.label.cell!.cellSize.height
        let iconCellSize = firstView.statusIcons.iconCellSize
        layoutCache.iconWidth = iconCellSize.width
        layoutCache.iconHeight = iconCellSize.height
        layoutCache.dockLabelSize = firstView.dockLabelIcon.frame.size
        layoutCache.comfortableReadabilityWidth = TileView.widthOfComfortableReadability()
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
        TilesPanel.updateMaxPossibleThumbnailSize()
        // app icons are captured once at launch; we need to manually update them if needed
        let old = TilesPanel.maxPossibleAppIconSize.width
        TilesPanel.updateMaxPossibleAppIconSize()
        if old != TilesPanel.maxPossibleAppIconSize.width {
            Applications.updateAppIcons()
        }
        updateBackgroundView()
        App.app.thumbnailsPanel.contentView = contentView
        for i in 0..<TilesView.recycledViews.count {
            TilesView.recycledViews[i] = TileView()
        }
        thumbnailUnderLayer = TileUnderLayer()
        thumbnailOverView = TileOverView()
        thumbnailOverView.scrollView = scrollView
        lastRowSignature.removeAll()
        Self.updateCachedSizes()
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        guard view.frame != .zero else { return }
        view.drawHighlight()
        let underLayer = App.app.thumbnailsPanel.tilesView.thumbnailUnderLayer
        let focusedView = recycledViews[Windows.selectedWindowIndex]
        let hoveredView = Windows.hoveredWindowIndex.map { recycledViews[$0] }
        underLayer.updateHighlight(
            focusedView: focusedView.frame != .zero ? focusedView : nil,
            hoveredView: hoveredView != focusedView && hoveredView?.frame != .zero ? hoveredView : nil
        )
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [TileView]? {
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
        guard Windows.selectedWindowIndex < TilesView.recycledViews.count else { return }
        let focusedViewFrame = TilesView.recycledViews[Windows.selectedWindowIndex].frame
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
        guard let targetIndex = TilesView.recycledViews.firstIndex(of: targetView) else { return }
        Windows.updateSelectedAndHoveredWindowIndex(targetIndex)
    }

    func updateItemsAndLayout(_ preservedScrollOrigin: CGPoint?) {
        let widthMax = TilesPanel.maxThumbnailsWidth().rounded()
        if let (maxX, maxY, labelHeight, rowSignature) = layoutTileViews(widthMax) {
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
            if let preservedScrollOrigin {
                restoreScrollOrigin(preservedScrollOrigin)
            }
        }
    }

    func currentScrollOrigin() -> CGPoint {
        scrollView.contentView.bounds.origin
    }

    private func restoreScrollOrigin(_ scrollOrigin: CGPoint) {
        guard let documentView = scrollView.documentView else { return }
        let visibleSize = scrollView.contentView.bounds.size
        let documentSize = documentView.frame.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let clampedOrigin = CGPoint(x: min(max(0, scrollOrigin.x), maxX), y: min(max(0, scrollOrigin.y), maxY))
        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func layoutTileViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat, [Int])? {
        let labelHeight = Self.layoutCache.labelHeight
        let height = TileView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [TileView]()
        var rowSignature = [Int]()
        rows.removeAll(keepingCapacity: true)
        rows.append([TileView]())
        var index = 0
        while index < TilesView.recycledViews.count {
            guard App.app.appIsBeingUsed else { return nil }
            defer { index = index + 1 }
            let view = TilesView.recycledViews[index]
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
                    rows.append([TileView]())
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
        scrollView.documentView!.addSubview(thumbnailOverView)
        thumbnailOverView.scrollView = scrollView
        let docLayer = scrollView.documentView!.layer!
        if thumbnailUnderLayer.superlayer !== docLayer {
            docLayer.insertSublayer(thumbnailUnderLayer, at: 0)
        }
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
        let heightMax = TilesPanel.maxThumbnailsHeight()
        TilesView.thumbnailsWidth = min(maxX, widthMax)
        TilesView.thumbnailsHeight = min(maxY, heightMax)
        let appIconsBottomViewportPadding = appIconsBottomViewportPadding(maxY, heightMax, labelHeight)
        let frameWidth = TilesView.thumbnailsWidth + Appearance.windowPadding * 2
        var frameHeight = TilesView.thumbnailsHeight + Appearance.windowPadding * 2
        let originX = Appearance.windowPadding
        var originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        let scrollHeight = max(0, min(maxY, heightMax) - appIconsBottomViewportPadding * 2)
        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: scrollHeight)
        scrollView.frame.origin = CGPoint(x: originX, y: originY + appIconsBottomViewportPadding * 2)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        let docSize = scrollView.documentView!.frame.size
        thumbnailOverView.frame = CGRect(origin: .zero, size: docSize)
        thumbnailUnderLayer.frame = CGRect(origin: .zero, size: docSize)
    }

    private func appIconsBottomViewportPadding(_ maxY: CGFloat, _ heightMax: CGFloat, _ labelHeight: CGFloat) -> CGFloat {
        guard Preferences.appearanceStyle == .appIcons, maxY > heightMax else { return 0 }
        return max(0, Appearance.windowPadding - labelHeight)
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = Appearance.interCellPadding
        var rowY = Appearance.interCellPadding
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return }
            guard window.shouldShowTheUser else { continue }
            let view = TilesView.recycledViews[index]
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
        TilesView.highlight(Windows.selectedWindowIndex)
        if let hoveredWindowIndex = Windows.hoveredWindowIndex {
            TilesView.highlight(hoveredWindowIndex)
            if thumbnailOverView.isShowingWindowControls {
                thumbnailOverView.showWindowControls(for: TilesView.recycledViews[hoveredWindowIndex])
            }
        }
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            for i in rowStartIndex..<index {
                TilesView.recycledViews[i].frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
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

    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
        documentView!.wantsLayer = true
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

    @objc private func scrollingStarted() { isCurrentlyScrolling = true }
    @objc private func scrollingEnded() { isCurrentlyScrolling = false }

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
