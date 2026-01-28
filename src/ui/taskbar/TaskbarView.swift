import Cocoa

class TaskbarView: NSView {
    private var effectView: NSVisualEffectView!
    private var scrollView: NSScrollView!
    private var documentView: NSView!
    private var itemViews = [TaskbarItemView]()
    private var itemHeight: CGFloat { Preferences.taskbarItemHeight }
    private let itemSpacing: CGFloat = 4
    private let horizontalPadding: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupView() {
        wantsLayer = true

        // background blur effect
        effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        if #available(macOS 10.14, *) {
            effectView.material = .hudWindow
        } else {
            effectView.material = .dark
        }
        effectView.wantsLayer = true
        addSubview(effectView)

        // scroll view for horizontal scrolling
        scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        // document view holds the items
        documentView = NSView()
        documentView.wantsLayer = true
        scrollView.documentView = documentView

        // pre-allocate some item views
        for _ in 0..<20 {
            let itemView = TaskbarItemView()
            itemView.isHidden = true
            documentView.addSubview(itemView)
            itemViews.append(itemView)
        }
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        scrollView.frame = bounds
    }

    func updateItems(_ windows: [Window]) {
        // ensure we have enough item views
        while itemViews.count < windows.count {
            let itemView = TaskbarItemView()
            itemView.isHidden = true
            documentView.addSubview(itemView)
            itemViews.append(itemView)
        }

        // calculate item width
        let maxItemWidth: CGFloat = 160
        let minItemWidth: CGFloat = 48

        var currentX = horizontalPadding
        let itemY = (bounds.height - itemHeight) / 2

        for (index, itemView) in itemViews.enumerated() {
            if index < windows.count {
                let window = windows[index]
                itemView.updateContent(window)

                // calculate width based on title
                let titleWidth = itemView.preferredWidth()
                let itemWidth = min(maxItemWidth, max(minItemWidth, titleWidth))

                let newFrame = NSRect(x: currentX, y: itemY, width: itemWidth, height: itemHeight)
                let frameChanged = itemView.frame != newFrame
                itemView.frame = newFrame
                itemView.isHidden = false

                // ensure tracking areas are updated when frame changes or view becomes visible
                if frameChanged {
                    itemView.updateTrackingAreas()
                }

                currentX += itemWidth + itemSpacing
            } else {
                itemView.isHidden = true
            }
        }

        // update document view size
        let totalWidth = max(currentX + horizontalPadding - itemSpacing, bounds.width)
        documentView.frame = NSRect(x: 0, y: 0, width: totalWidth, height: bounds.height)
    }
}
