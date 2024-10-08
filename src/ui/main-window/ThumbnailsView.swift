import Cocoa

class ThumbnailsView: NSVisualEffectView {
    let scrollView = ScrollView()
    static var recycledViews = [ThumbnailView]()
    var rows = [[ThumbnailView]]()
    static var thumbnailsWith = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)

    convenience init() {
        self.init(frame: .zero)
        material = Appearance.material
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        updateRoundedCorners(Appearance.windowCornerRadius)
        addSubview(scrollView)
        // TODO: think about this optimization more
        (1...100).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
    }

    func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        Appearance.update()
        self.material = Appearance.material
        ThumbnailsView.recycledViews = ThumbnailsView.recycledViews.map { _ in ThumbnailView() }
        updateRoundedCorners(Appearance.windowCornerRadius)
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        if view.frame != NSRect.zero {
            view.drawHighlight()
        }
    }

    /// using layer!.cornerRadius works but the corners are aliased; this custom approach gives smooth rounded corners
    /// see https://stackoverflow.com/a/29386935/2249756
    func updateRoundedCorners(_ cornerRadius: CGFloat) {
        if cornerRadius == 0 {
            maskImage = nil
        } else {
            let edgeLength = 2.0 * cornerRadius + 1.0
            let mask = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
                let bezierPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.black.set()
                bezierPath.fill()
                return true
            }
            mask.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
            mask.resizingMode = .stretch
            maskImage = mask
        }
    }

    func nextRow(_ direction: Direction) -> [ThumbnailView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.focusedWindow()?.rowIndex {
            let nextRow = (currentRow + step) % rows.count
            let nextRow_ = nextRow < 0 ? rows.count + nextRow : nextRow
            if ((step > 0 && nextRow_ < currentRow) || (step < 0 && nextRow_ > currentRow)) &&
                   (KeyRepeatTimer.isARepeat || KeyRepeatTimer.timer?.isValid ?? false) {
                return nil
            }
            return rows[nextRow_]
        }
        return nil
    }

    func navigateUpOrDown(_ direction: Direction) {
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.focusedWindowIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        if let targetRow = nextRow(direction) {
            let leftSide = originCenter < NSMidX(frame)
            let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
            let iterable = leadingSide ? targetRow : targetRow.reversed()
            let targetView = iterable.first {
                if App.shared.userInterfaceLayoutDirection == .leftToRight {
                    return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
                }
                return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
            } ?? iterable.last!
            let targetIndex = ThumbnailsView.recycledViews.firstIndex(of: targetView)!
            Windows.updateFocusedAndHoveredWindowIndex(targetIndex)
        }
    }

    func updateItemsAndLayout(_ screen: NSScreen) {
        let widthMax = ThumbnailsPanel.maxThumbnailsWidth(screen).rounded()
        if let (maxX, maxY) = layoutThumbnailViews(screen, widthMax) {
            layoutParentViews(screen, maxX, widthMax, maxY)
            if Preferences.alignThumbnails == .center {
                centerRows(maxX)
            }
            for (i, row) in rows.enumerated() {
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

    private func layoutThumbnailViews(_ screen: NSScreen, _ widthMax: CGFloat) -> (CGFloat, CGFloat)? {
        let height = ThumbnailView.height(screen)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [ThumbnailView]()
        rows.removeAll()
        rows.append([ThumbnailView]())
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return nil }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            view.updateRecycledCellWithNewContent(window, index, height, screen)
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
        }
        scrollView.documentView!.subviews = newViews
        return (maxX, maxY)
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

    private func layoutParentViews(_ screen: NSScreen, _ maxX: CGFloat, _ widthMax: CGFloat, _ maxY: CGFloat) {
        let heightMax = ThumbnailsPanel.maxThumbnailsHeight(screen).rounded()

        ThumbnailsView.thumbnailsWith = min(maxX, widthMax)
        ThumbnailsView.thumbnailsHeight = min(maxY, heightMax)
        var frameWidth = ThumbnailsView.thumbnailsWith + Appearance.windowPadding * 2
        var frameHeight = ThumbnailsView.thumbnailsHeight + Appearance.windowPadding * 2
        var originX = Appearance.windowPadding
        var originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - ThumbnailTitleView.maxHeight()
            originY = originY - Appearance.intraCellPadding - ThumbnailTitleView.maxHeight()
        }
        frame.size = NSSize(width: frameWidth, height: frameHeight)

        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: min(maxY, heightMax))
        scrollView.frame.origin = CGPoint(x: originX, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
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
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            (rowStartIndex..<index).forEach {
                ThumbnailsView.recycledViews[$0].frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
            }
        }
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
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        forceOverlayStyle()
        observeScrollingEvents()
    }

    private func observeScrollingEvents() {
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: nil, queue: nil) { [weak self] _ in
            self?.isCurrentlyScrolling = false
        }
        NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: nil, queue: nil) { [weak self] _ in
            self?.isCurrentlyScrolling = true
        }
    }

    private func resetHoveredWindow() {
        if let oldIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
            ThumbnailsView.recycledViews[oldIndex].showOrHideWindowControls(false)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // disable mouse hover during scrolling as it creates jank during elastic bounces at the start/end of the scrollview
        if isCurrentlyScrolling { return }
        if let hit = hitTest(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream) {
            var target: NSView? = hit
            while !(target is ThumbnailView) && target != nil {
                target = target!.superview
            }
            if let target = target, target is ThumbnailView {
                if previousTarget != target {
                    previousTarget?.showOrHideWindowControls(false)
                    previousTarget = target as? ThumbnailView
                }
                let target = target as! ThumbnailView
                target.mouseMoved()
            } else {
                if !checkIfWithinInterPadding() {
                    resetHoveredWindow()
                }
            }
        } else {
            resetHoveredWindow()
        }
    }

    override func mouseExited(with event: NSEvent) {
        resetHoveredWindow()
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

    /// force overlay style after a change in System Preference > General > Show scroll bars
    private func forceOverlayStyle() {
        NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.scrollerStyle = .overlay
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
