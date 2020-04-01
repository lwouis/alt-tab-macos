import Cocoa

class ThumbnailsView: NSVisualEffectView {
    let scrollView = ScrollView()
    static var recycledViews = [ThumbnailView]()

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

    func updateItems(_ screen: NSScreen) {
        let widthMax = ThumbnailsPanel.widthMax(screen).rounded()
        let heightMax = ThumbnailsPanel.heightMax(screen).rounded()
        let height = ThumbnailView.height(screen).rounded(.down)
        var currentX = CGFloat(0)
        var currentY = CGFloat(0)
        var maxX = CGFloat(0)
        var maxY = height
        var newViews = [ThumbnailView]()
        for (index, window) in Windows.list.enumerated() {
            let view = ThumbnailsView.recycledViews[index]
            view.updateRecycledCellWithNewContent(window,
                    { App.app.focusSelectedWindow(window) },
                    { Windows.updateFocusedWindowIndex(index) },
                    height, screen)
            let width = view.frame.size.width
            if (currentX + Preferences.interCellPadding + width).rounded(.down) > widthMax {
                currentX = CGFloat(0)
                currentY = (currentY + Preferences.interCellPadding + height).rounded(.down)
                maxY = max(currentY + height, maxY)
            } else {
                maxX = max(currentX + width, maxX)
            }
            view.frame.origin = CGPoint(x: currentX, y: currentY)
            currentX = (currentX + Preferences.interCellPadding + width).rounded(.down)
            newViews.append(view)
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
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = CGFloat(0)
        var rowY = CGFloat(0)
        for (index, _) in Windows.list.enumerated() {
            let view = ThumbnailsView.recycledViews[index]
            if view.frame.origin.y == rowY {
                rowWidth += Preferences.interCellPadding + view.frame.size.width
            } else {
                if rowStartIndex == 0 {
                    rowWidth -= Preferences.interCellPadding // first row has 1 extra padding
                }
                shiftRow(maxX, rowWidth, rowStartIndex, index)
                rowStartIndex = index
                rowWidth = view.frame.size.width
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
    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
    }

    override func tile() {
        super.tile()
        // draw the scroller on top of the content
        contentView.frame = bounds
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}