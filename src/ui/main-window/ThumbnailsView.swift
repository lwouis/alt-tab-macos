import Cocoa

class ThumbnailsView: NSVisualEffectView {
    let scrollView = ScrollView()
    static var recycledViews = [ThumbnailView]()
    var rows = [[ThumbnailView]]()

    convenience init() {
        self.init(frame: .zero)
        material = Preferences.windowMaterial
        state = .active
        wantsLayer = true
        layer!.cornerRadius = Preferences.windowCornerRadius
        addSubview(scrollView)
        // TODO: think about this optimization more
        (1...100).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
    }

    func nextRow(_ direction: Direction) -> [ThumbnailView] {
        let step = direction == .down ? 1 : -1
        let indexAfterStep = (Windows.focusedWindow()!.row! + step) % rows.count
        let targetRowIndex = indexAfterStep < 0 ? rows.count + indexAfterStep : indexAfterStep
        return rows[targetRowIndex]
    }

    func navigateUpOrDown(_ direction: Direction) {
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.focusedWindowIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        let targetRow = nextRow(direction)
        let leftSide = originCenter < NSMidX(frame)
        let iterable = leftSide ? targetRow : targetRow.reversed()
        let targetView = iterable.first(where: {
            leftSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
        }) ?? iterable.last!
        let targetIndex = ThumbnailsView.recycledViews.firstIndex(of: targetView)!
        Windows.updateFocusedWindowIndex(targetIndex)
    }

    func updateItems(_ screen: NSScreen) {
        let widthMax = ThumbnailsPanel.widthMax(screen).rounded()
        let heightMax = ThumbnailsPanel.heightMax(screen).rounded()
        let height = ThumbnailView.height(screen).rounded(.down)
        var currentX = Preferences.interCellPadding
        var currentY = Preferences.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Preferences.interCellPadding
        var newViews = [ThumbnailView]()
        rows.removeAll()
        rows.append([ThumbnailView]())
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            view.updateRecycledCellWithNewContent(window, index, height, screen)
            let width = view.frame.size.width
            if (currentX + width + Preferences.interCellPadding).rounded(.down) > widthMax {
                currentX = Preferences.interCellPadding
                currentY = (currentY + height + Preferences.interCellPadding).rounded(.down)
                maxY = max(currentY + height + Preferences.interCellPadding, maxY)
                rows.append([ThumbnailView]())
            } else {
                maxX = max(currentX + width + Preferences.interCellPadding, maxX)
            }
            view.frame.origin = CGPoint(x: currentX, y: currentY)
            currentX = (currentX + Preferences.interCellPadding + width).rounded(.down)
            newViews.append(view)
            rows[rows.count - 1].append(view)
            window.row = rows.count - 1
        }
        scrollView.documentView!.subviews = newViews
        frame.size = NSSize(width: min(maxX, widthMax) + Preferences.windowPadding * 2, height: min(maxY, heightMax) + Preferences.windowPadding * 2)
        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: min(maxY, heightMax))
        scrollView.frame.origin = CGPoint(x: Preferences.windowPadding, y: Preferences.windowPadding)
        scrollView.contentView.frame.size = scrollView.frame.size
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        if Preferences.alignThumbnails == .center {
            centerRows(maxX)
        }
        Windows.list.enumerated().first { (index, _) in
            let view = ThumbnailsView.recycledViews[index]
            if view.isHighlighted {
                view.highlightOrNot()
            }
            return view.isHighlighted
        }
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = Preferences.interCellPadding
        var rowY = Preferences.interCellPadding
        for (index, _) in Windows.list.enumerated() {
            let view = ThumbnailsView.recycledViews[index]
            if view.frame.origin.y == rowY {
                rowWidth += view.frame.size.width + Preferences.interCellPadding
            } else {
                shiftRow(maxX, rowWidth, rowStartIndex, index)
                rowStartIndex = index
                rowWidth = Preferences.interCellPadding + view.frame.size.width + Preferences.interCellPadding
                rowY = view.frame.origin.y
            }
        }
        shiftRow(maxX, rowWidth, rowStartIndex, Windows.list.count)
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            (rowStartIndex..<index).forEach {
                ThumbnailsView.recycledViews[$0].frame.origin.x += offset
            }
        }
    }
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

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
    }

    // holding shift and using the scrolling wheel will generate a horizontal movement
    // shift can be part of shortcuts so we force shift scrolls to be vertical
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

    // force overlay style after a change in System Preference > General > Show scroll bars
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
    case neutral
    case left
    case right
    case up
    case down

    func step() -> Int {
        if self == .left {
            return -1
        } else if self == .right {
            return 1
        }
        return 0
    }
}
