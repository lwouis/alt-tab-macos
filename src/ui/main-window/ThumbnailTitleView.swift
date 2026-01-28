import Cocoa

class ThumbnailTitleView: NSTextField {
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
        frame.size.width = width
        // TODO: NSTextField does some internal magic, and ends up with constraints.
        // we can't use addOrUpdateConstraint for some reason, otherwise it will only actually apply after the UI is shown twice
        // i tried everything and ended up removing all constraints then adding a fresh one. This seems to work
        let toRemove = constraints.filter {
            ($0.firstItem as? NSView) === self && $0.firstAttribute == .width ||
                ($0.secondItem as? NSView) === self && $0.secondAttribute == .width
        }
        toRemove.forEach { removeConstraint($0) }
        widthAnchor.constraint(equalToConstant: width).isActive = true
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
