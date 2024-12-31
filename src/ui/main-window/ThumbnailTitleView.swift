import Cocoa

class ThumbnailTitleView: NSTextField {
    convenience init(shadow: NSShadow?, font: NSFont) {
        self.init(labelWithString: "")
        self.font = font
        textColor = Appearance.fontColor
        self.shadow = shadow
        allowsDefaultTighteningForTruncation = false
        translatesAutoresizingMaskIntoConstraints = false
    }

    func fixHeight() {
        heightAnchor.constraint(equalToConstant: cell!.cellSize.height).isActive = true
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
