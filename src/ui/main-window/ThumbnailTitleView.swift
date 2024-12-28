import Cocoa

class ThumbnailTitleView: NSTextField {
    convenience init(shadow: NSShadow?, font: NSFont) {
        self.init(labelWithString: "")
        self.font = font
        textColor = Appearance.fontColor
        self.shadow = shadow
        lineBreakMode = getTruncationMode()
        allowsDefaultTighteningForTruncation = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    func fixHeight() {
        heightAnchor.constraint(equalToConstant: cell!.cellSize.height).isActive = true
    }

    override func mouseMoved(with event: NSEvent) {
        // no-op here prevents tooltips from disappearing on mouseMoved
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
