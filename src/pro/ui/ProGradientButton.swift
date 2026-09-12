import Cocoa

class ProGradientButton: NSButton {
    static let cornerRadius = CGFloat(7)

    private var isPressed = false
    private var isShining = false
    let gradientLayer = ProGradient.makeLayer(flipped: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isBordered = false
        cell?.wraps = true
        layer?.cornerRadius = ProGradientButton.cornerRadius
        gradientLayer.cornerRadius = ProGradientButton.cornerRadius
        gradientLayer.masksToBounds = true
        layer?.insertSublayer(gradientLayer, at: 0)
        shadow = NSShadow()
        layer?.shadowColor = ProGradient.representativeColor.withAlphaComponent(0.5).cgColor
        layer?.shadowOpacity = 0.8
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds,
            cornerWidth: ProGradientButton.cornerRadius,
            cornerHeight: ProGradientButton.cornerRadius,
            transform: nil)
        CATransaction.commit()
    }

    override func updateLayer() {
        super.updateLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.opacity = isPressed ? 0.82 : 1.0
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) {
        playShineAnimation()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
        updateLayer()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        updateLayer()
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            sendAction(action, to: target)
        }
    }

    func playShineAnimation() {
        guard !isShining else { return }
        isShining = true
        ProGradient.playShine(over: gradientLayer) { [weak self] in self?.isShining = false }
    }
}
