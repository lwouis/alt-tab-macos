import Cocoa

class TileTitleView: NSTextField {
    static let searchHighlightBackgroundKey = NSAttributedString.Key("tileSearchHighlightBackground")
    private var currentWidth: CGFloat = -1

    // we set their size manually; override this to remove wasteful appkit-side work
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    /// `NSView` is its own `CALayerDelegate`. By implementing `action(for:forKey:)` on this
    /// subclass we intercept the lookup AppKit performs when a layer property changes, and
    /// return `NSNull()` for the animation keys — the documented "no animation for this key"
    /// sentinel. Without this, the label slides smoothly from its previous-style position
    /// during a cross-style summon (e.g. right-of-icon → under-icon when going thumbnails →
    /// appIcons), because `caTransaction { setDisableActions(true) }` in `TilesPanel.updateContents`
    /// doesn't cover the follow-up layout pass that `NSWindow.setContentSize` triggers outside
    /// the transaction.
    ///
    /// Not marked `override`: `NSView`'s `CALayerDelegate` conformance is via Objective-C and
    /// Swift doesn't expose the method as overridable. Providing it here at the Swift level
    /// installs it for the runtime to find when the layer asks the delegate for actions.
    @objc func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "position", "bounds", "frame", "hidden", "opacity", "transform":
            return NSNull()
        default:
            return nil
        }
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

    /// Re-apply appearance-baked font/color so a recycled instance survives an appearance change
    /// without being reallocated (which would free this tooltip owner; see TileView.reapplyAppearance).
    func reapplyAppearance() {
        font = Appearance.font
        textColor = Appearance.fontColor
        fixHeight()
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
