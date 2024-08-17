import Cocoa

class Switch: NSControl {

    private class SwitchView: NSView {

        var isOn: Bool = false {
            didSet {
                animateKnob()
                needsDisplay = true
            }
        }

        var switchWidth: CGFloat {
            didSet {
                self.needsLayout = true
                self.needsDisplay = true
                layoutKnobView()
            }
        }

        var switchHeight: CGFloat {
            didSet {
                self.needsLayout = true
                self.needsDisplay = true
                layoutKnobView()
            }
        }

        private let knobView = NSView()

        init(width: CGFloat, height: CGFloat) {
            self.switchWidth = width
            self.switchHeight = height
            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false
            setupKnobView()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            return NSSize(width: switchWidth, height: switchHeight)
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let switchRect = NSInsetRect(bounds, 1, 1)
            let path = NSBezierPath(roundedRect: switchRect, xRadius: switchRect.height / 2, yRadius: switchRect.height / 2)

            // Background
            (isOn ? systemAccentColor() : NSColor.systemGray).setFill()
            path.fill()
        }

        override func mouseDown(with event: NSEvent) {
            isOn.toggle()
            if let control = superview as? Switch {
                control.state = isOn ? .on : .off
                control.sendAction(control.action, to: control.target)
            }
        }

        private func systemAccentColor() -> NSColor {
            if #available(macOS 10.14, *) {
                return NSColor.controlAccentColor
            } else {
                return NSColor.systemBlue
            }
        }

        private func setupKnobView() {
            knobView.wantsLayer = true
            knobView.layer?.backgroundColor = NSColor.white.cgColor
            addSubview(knobView)
            layoutKnobView()
        }

        private func layoutKnobView() {
            let knobSize = NSSize(width: switchHeight - 4, height: switchHeight - 4)
            knobView.frame = NSRect(x: isOn ? switchWidth - knobSize.width - 2 : 2, y: 2, width: knobSize.width, height: knobSize.height)
            knobView.layer?.cornerRadius = knobSize.height / 2
        }

        private func animateKnob() {
            let knobSize = NSSize(width: switchHeight - 4, height: switchHeight - 4)
            let finalKnobX = isOn ? switchWidth - knobSize.width - 2 : 2

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                knobView.animator().frame.origin.x = finalKnobX
            }
        }
    }

    var state: NSControl.StateValue {
        get {
            return switchView.isOn ? .on : .off
        }
        set {
            switchView.isOn = (newValue == .on)
        }
    }

    private let switchView: SwitchView

    init(_ checked: Bool = false, width: CGFloat = 28, height: CGFloat = 17) {
        switchView = SwitchView(width: width, height: height)
        switchView.isOn = checked

        super.init(frame: .zero)

        addSubview(switchView)
        NSLayoutConstraint.activate([
            switchView.widthAnchor.constraint(equalToConstant: width),
            switchView.heightAnchor.constraint(equalToConstant: height),
            switchView.centerXAnchor.constraint(equalTo: centerXAnchor),
            switchView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: switchView.switchWidth, height: switchView.switchHeight)
    }

    // Method to dynamically adjust the width and height of the switch
    func setDimensions(width: CGFloat, height: CGFloat) {
        switchView.switchWidth = width
        switchView.switchHeight = height

        NSLayoutConstraint.deactivate(switchView.constraints)
        NSLayoutConstraint.activate([
            switchView.widthAnchor.constraint(equalToConstant: width),
            switchView.heightAnchor.constraint(equalToConstant: height),
        ])

        invalidateIntrinsicContentSize()
    }
}
