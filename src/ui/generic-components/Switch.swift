import Cocoa

class Switch: NSButton {

    private let knobView = NSView()

    init(_ checked: Bool = false, width: CGFloat = 28, height: CGFloat = 17) {
        super.init(frame: .zero)

        // Set button style to borderless
        self.bezelStyle = .regularSquare
        self.isBordered = false
        self.title = ""
        self.setButtonType(.toggle)
        self.state = checked ? .on : .off

        knobView.wantsLayer = true
        knobView.layer?.backgroundColor = NSColor.switchKnobColor.cgColor
        knobView.layer?.borderColor = NSColor.switchBorderColor.cgColor
        addSubview(knobView)
        layoutKnob()

        let knobSize = NSSize(width: height - 4, height: height - 4)
        knobView.layer?.cornerRadius = knobSize.height / 2

        self.setFrameSize(NSSize(width: width, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return frame.size
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Define the rectangle in which the switch will be drawn, inset by 1 point from the view's bounds.
        let switchRect = NSInsetRect(bounds, 1, 1)
        // Create a rounded rectangle path for the switch background.
        let path = NSBezierPath(roundedRect: switchRect, xRadius: switchRect.height / 2, yRadius: switchRect.height / 2)

        // Draw background
        (state == .on ? NSColor.systemAccentColor : NSColor.switchOffBackgroundColor).setFill()
        path.fill()

        // Draw border
        let borderColor = getBorderColor()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        knobView.layer?.backgroundColor = NSColor.switchKnobColor.cgColor
        knobView.layer?.borderColor = NSColor.switchBorderColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        state = (state == .on) ? .off : .on
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        sendAction(action, to: target)
    }

    override var state: NSControl.StateValue {
        didSet {
            animateKnob()
            needsDisplay = true
        }
    }

    private func layoutKnob() {
        let knobSize = NSSize(width: frame.height - 4, height: frame.height - 4)
        knobView.frame = NSRect(x: (state == .on) ? frame.width - knobSize.width - 2 : 2, y: 2, width: knobSize.width, height: knobSize.height)
        knobView.layer?.backgroundColor = NSColor.switchKnobColor.cgColor
        knobView.layer?.borderColor = NSColor.switchBorderColor.cgColor
    }

    private func animateKnob() {
        let knobSize = NSSize(width: frame.height - 4, height: frame.height - 4)
        let finalKnobX = (state == .on) ? frame.width - knobSize.width - 2 : 2

        NSAnimationContext.runAnimationGroup { context in
            context.allowsImplicitAnimation = false
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            knobView.animator().frame.origin.x = finalKnobX
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutKnob()
        needsDisplay = true
    }

    private func getBorderColor() -> NSColor {
        return (state == .on) ? NSColor.systemAccentColor : NSColor.switchBorderColor
    }
}
