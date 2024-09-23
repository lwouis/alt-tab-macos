import Cocoa

class WindowlessAppIndicator: NSView {
    var color: NSColor!
    var size: CGFloat!

    convenience init(color: NSColor = Appearance.fontColor, size: CGFloat = 5, tooltip: String? = nil) {
        self.init(frame: .zero)
        self.color = color
        self.size = size
        self.toolTip = tooltip
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()

        let radius = min(bounds.size.width, bounds.size.height) / 2
        let center = CGPoint(x: bounds.size.width / 2, y: bounds.size.height / 2)

        // Draw a circle
        let circlePath = NSBezierPath()
        circlePath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        circlePath.close()

        circlePath.fill()
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}