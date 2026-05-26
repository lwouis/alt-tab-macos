import Cocoa

/// A lightweight, read-only label drawn directly via `NSAttributedString.draw(in:)` — bypasses
/// `NSTextField` / `NSCell` / TextKit2 / SwiftUI rendering paths.
///
/// `NSTextField(labelWithString:)` is a Swiss-army knife: editable, selectable, IME-aware,
/// focusable, find-and-replace-capable, accessibility-integrated, dynamic-type-scaling, etc. For
/// each of those features it pays a per-redraw cost. With hundreds of labels in a window and a
/// `_windowChangedKeyState` cascade firing on every focus change, those costs compound into a
/// perceptible hang.
///
/// `LightLabel` skips that machinery: it's an `NSView` whose `draw(_:)` renders the text via
/// `NSAttributedString.draw(in:)` (which goes through CoreText, not TextKit2). Per-redraw cost
/// is a fraction of `NSTextField`'s. Functionality is intentionally limited to "show some text":
/// no editing, no selection, no focus ring, no IME. Accessibility is registered as `.staticText`.
///
/// Drop-in compatible with the subset of `NSTextField` properties our row-label sites use:
/// `stringValue`, `attributedStringValue`, `textColor`, `font`, `alignment`, `lineBreakMode`,
/// `maximumNumberOfLines`. Search-highlight is built in via `applyHighlight` / `clearHighlight`.
final class LightLabel: NSView {
    /// The plain-text content. Setting this clears any explicit `attributedStringValue` override.
    var stringValue: String = "" {
        didSet {
            guard stringValue != oldValue else { return }
            attributedOverride = nil
            invalidateContentCache()
            setAccessibilityLabel(stringValue)
        }
    }

    /// Optional rich-text override. When non-nil, takes precedence over `stringValue` + the
    /// font/color/alignment properties for rendering. Used by callers that need attribute runs
    /// (e.g. mixed gradient text). Setting `stringValue` clears this back to nil.
    var attributedStringValue: NSAttributedString? {
        get { attributedOverride }
        set {
            attributedOverride = newValue
            if let newValue { stringValueBacking = newValue.string }
            invalidateContentCache()
        }
    }

    var textColor: NSColor = .labelColor {
        didSet { if textColor != oldValue { needsDisplay = true } }
    }
    var font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize) {
        didSet {
            guard font != oldValue else { return }
            invalidateContentCache()
        }
    }
    var alignment: NSTextAlignment = .left {
        didSet { if alignment != oldValue { needsDisplay = true } }
    }
    var lineBreakMode: NSLineBreakMode = .byTruncatingTail {
        didSet {
            guard lineBreakMode != oldValue else { return }
            invalidateContentCache()
        }
    }
    var maximumNumberOfLines: Int = 1 {
        didSet {
            guard maximumNumberOfLines != oldValue else { return }
            invalidateContentCache()
        }
    }

    /// Optional foreground tint applied to `highlightRanges` (typically the search-match color
    /// rendered on top of the yellow rounded background). When `highlightRanges` is empty, this
    /// has no effect.
    var highlightForegroundColor: NSColor = .labelColor
    private(set) var highlightRanges: [NSRange] = []

    // Internal — the renderer reaches through these. We keep `stringValueBacking` separate from
    // `stringValue`'s storage so an attributedStringValue assignment can still expose the right
    // string to `searchableStrings`-style consumers without losing the original setter semantics.
    private var stringValueBacking: String { get { stringValue } set { stringValueRaw = newValue } }
    private var stringValueRaw: String {
        get { return stringValue }
        set { stringValue = newValue }
    }
    private var attributedOverride: NSAttributedString?
    private var cachedIntrinsicSize: NSSize?
    private var lastIntrinsicWidth: CGFloat = -1

    init(_ string: String = "") {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        if !string.isEmpty {
            stringValue = string
            setAccessibilityLabel(string)
        }
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func isAccessibilityElement() -> Bool { true }

    /// Mark the given character ranges to render with `highlightForegroundColor` (typically the
    /// search-match color). Triggers a redraw. The yellow rounded background is applied
    /// separately via `SettingsWindow.applyRoundedHighlights`.
    func applyHighlight(ranges: [NSRange], foregroundColor: NSColor) {
        highlightRanges = ranges
        highlightForegroundColor = foregroundColor
        needsDisplay = true
    }

    func clearHighlight() {
        guard !highlightRanges.isEmpty else { return }
        highlightRanges = []
        needsDisplay = true
    }

    private func invalidateContentCache() {
        cachedIntrinsicSize = nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.alignment = alignment
        p.lineBreakMode = lineBreakMode
        return p
    }

    /// The attributed string actually rendered. Built from `attributedStringValue` if set,
    /// otherwise from `stringValue` + the textColor/font/alignment/lineBreakMode properties.
    /// Any `highlightRanges` are layered on top of the base.
    private func renderedAttributedString() -> NSAttributedString {
        let base: NSAttributedString
        if let attributedOverride {
            base = attributedOverride
        } else {
            base = NSAttributedString(string: stringValue, attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle(),
            ])
        }
        guard !highlightRanges.isEmpty else { return base }
        let mutable = NSMutableAttributedString(attributedString: base)
        for range in highlightRanges where range.location >= 0 && range.upperBound <= mutable.length {
            mutable.addAttribute(.foregroundColor, value: highlightForegroundColor, range: range)
        }
        return mutable
    }

    override var intrinsicContentSize: NSSize {
        if let cached = cachedIntrinsicSize, lastIntrinsicWidth == bounds.width {
            return cached
        }
        guard !stringValue.isEmpty || attributedOverride != nil else {
            let size = NSSize(width: 0, height: ceil(font.ascender - font.descender))
            cachedIntrinsicSize = size
            lastIntrinsicWidth = bounds.width
            return size
        }
        let attr = renderedAttributedString()
        let size: NSSize
        if maximumNumberOfLines == 1 {
            let measured = attr.size()
            size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        } else {
            let width = bounds.width > 0 ? bounds.width : 10000
            let rect = attr.boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            size = NSSize(width: ceil(rect.width), height: ceil(rect.height))
        }
        cachedIntrinsicSize = size
        lastIntrinsicWidth = bounds.width
        return size
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !stringValue.isEmpty || attributedOverride != nil else { return }
        let attr = renderedAttributedString()
        let drawingRect: NSRect
        if maximumNumberOfLines == 1 {
            // Vertically center single-line text within the view bounds. NSAttributedString.draw
            // draws starting at the rect's top; with `isFlipped = true`, top is `y = 0`, so we
            // shift by half the leftover space.
            let textSize = attr.size()
            let y = max(0, (bounds.height - textSize.height) / 2)
            drawingRect = NSRect(x: 0, y: y, width: bounds.width, height: textSize.height)
        } else {
            drawingRect = bounds
        }
        // Yellow rounded backgrounds for search-match ranges sit *under* the text. We render them
        // inline (instead of as `CAShapeLayer` overlays the way `NSTextField` does) because we
        // own the entire draw path here and a single attributed string + glyph-range pass is
        // cheaper than juggling sublayers.
        if !highlightRanges.isEmpty {
            drawHighlightBackgrounds(attributedString: attr, in: drawingRect)
        }
        attr.draw(in: drawingRect)
    }

    private func drawHighlightBackgrounds(attributedString: NSAttributedString, in rect: NSRect) {
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: rect.width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = maximumNumberOfLines
        textContainer.lineBreakMode = lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        Appearance.searchMatchHighlightColor.setFill()
        let isRTL = userInterfaceLayoutDirection == .rightToLeft
        for range in highlightRanges where range.location >= 0 && range.upperBound <= attributedString.length {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { glyphRect, _ in
                var bgRect = glyphRect.offsetBy(dx: rect.minX, dy: rect.minY)
                bgRect = bgRect.insetBy(dx: -2, dy: -1)
                // Trim a sliver off the leading edge for visual breathing room between adjacent
                // highlights of separate words. Mirror direction for RTL.
                let trim: CGFloat = 1
                if isRTL {
                    bgRect = NSRect(x: bgRect.minX, y: bgRect.minY, width: max(bgRect.width - trim, 0.5), height: bgRect.height)
                } else {
                    bgRect = NSRect(x: bgRect.minX + trim, y: bgRect.minY, width: max(bgRect.width - trim, 0.5), height: bgRect.height)
                }
                NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}
