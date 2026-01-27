import Cocoa

class ThumbnailTitleView: NSTextField {
    private var cachedWidth: CGFloat = 0
    private var widthConstraint: NSLayoutConstraint?
    
    convenience init(font: NSFont) {
        self.init(labelWithString: "")
        self.font = font
        textColor = Appearance.fontColor
        // drawsBackground = true
        // backgroundColor = .red
        allowsDefaultTighteningForTruncation = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    func fixHeight() {
        heightAnchor.constraint(equalToConstant: fittingSize.height).isActive = true
    }

    func setWidth(_ width: CGFloat) {
        // Workaround for macOS 15+ hang: avoid recreating constraints if width hasn't changed
        // see https://github.com/lwouis/alt-tab-macos/issues/5177
        guard cachedWidth != width else { return }
        cachedWidth = width
        
        frame.size.width = width
        
        // Workaround for macOS 15+ hang: reuse existing constraint instead of removing/recreating
        // Updating constraint.constant is much cheaper than removeConstraint + new constraint
        if let existingConstraint = widthConstraint {
            existingConstraint.constant = width
        } else {
            // First time: remove any existing width constraints and create our tracked one
            let toRemove = constraints.filter {
                ($0.firstItem as? NSView) === self && $0.firstAttribute == .width ||
                    ($0.secondItem as? NSView) === self && $0.secondAttribute == .width
            }
            toRemove.forEach { removeConstraint($0) }
            widthConstraint = widthAnchor.constraint(equalToConstant: width)
            widthConstraint!.isActive = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // no-op here prevents tooltips from disappearing on mouseMoved
    }

    func updateTruncationModeIfNeeded() {
        let newLineBreakMode = getTruncationMode()
        if lineBreakMode != newLineBreakMode {
            lineBreakMode = newLineBreakMode
        }
    }

    private func getTruncationMode() -> NSLineBreakMode {
        if Preferences.titleTruncation == .end {
            return .byTruncatingTail
        }
        if Preferences.titleTruncation == .middle {
            return .byTruncatingMiddle
        }
        return .byTruncatingHead
    }
}
