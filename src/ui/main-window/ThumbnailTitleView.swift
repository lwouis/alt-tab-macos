import Cocoa

class ThumbnailTitleView: NSTextField {
    private var currentWidth: CGFloat = -1

    // we set their size manually; override this to remove wasteful appkit-side work
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    convenience init(font: NSFont) {
        self.init(frame: .zero)
        stringValue = ""
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        self.font = font
        textColor = Appearance.fontColor
        lineBreakMode = .byTruncatingTail
        allowsDefaultTighteningForTruncation = false
    }

    func fixHeight() {
        frame.size.height = cell!.cellSize.height
    }

    func setWidth(_ width: CGFloat) {
        guard currentWidth != width else { return }
        currentWidth = width
        frame.size.width = width
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
