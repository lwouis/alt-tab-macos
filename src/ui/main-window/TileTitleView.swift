import Cocoa

class TileTitleView: NSTextField {
    static let searchHighlightBackgroundKey = NSAttributedString.Key("tileSearchHighlightBackground")
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

    override func draw(_ dirtyRect: NSRect) {
        drawRoundedSearchHighlights()
        super.draw(dirtyRect)
    }

    func fixHeight() {
        frame.size.height = cell!.cellSize.height
    }

    func setWidth(_ width: CGFloat) {
        guard currentWidth != width else { return }
        currentWidth = width
        frame.size.width = width
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

    private func drawRoundedSearchHighlights() {
        let attributed = attributedStringValue
        guard attributed.length > 0 else { return }
        var hasHighlights = false
        attributed.enumerateAttribute(Self.searchHighlightBackgroundKey, in: NSRange(location: 0, length: attributed.length)) { value, _, stop in
            if value != nil {
                hasHighlights = true
                stop.pointee = true
            }
        }
        guard hasHighlights else { return }
        let textRect = cell?.drawingRect(forBounds: bounds) ?? bounds
        guard textRect.width > 0, textRect.height > 0 else { return }
        let storage = NSTextStorage(attributedString: attributed)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: textRect.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 1
        container.lineBreakMode = .byClipping
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        attributed.enumerateAttribute(Self.searchHighlightBackgroundKey, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let glyphRect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            guard glyphRect.width > 0, glyphRect.height > 0 else { return }
            var rect = glyphRect
            rect.origin.x += textRect.origin.x + 1.05
            rect.origin.y += textRect.origin.y + 0.45
            rect.size.width += 0.75
            rect.size.height = max(1, rect.size.height - 0.9)
            rect = pixelAligned(rect)
            let radius = min(4, rect.height * 0.35)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func pixelAligned(_ rect: NSRect) -> NSRect {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        var result = rect
        result.origin.x = round(result.origin.x * scale) / scale
        result.origin.y = round(result.origin.y * scale) / scale
        result.size.width = max(1 / scale, ceil(result.size.width * scale) / scale)
        result.size.height = max(1 / scale, ceil(result.size.height * scale) / scale)
        return result
    }
}
