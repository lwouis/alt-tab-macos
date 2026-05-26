import Cocoa

/// A closure-bag that knows how to test a search query against one specific control's text and
/// apply / clear the yellow search highlight on it. Produced by the `SettingsSearchHighlight`
/// factories below (and a couple still living on `SettingsWindow` for controls whose highlight is
/// tied to the window's sheet lifecycle), collected per-section by `SettingsSearchIndex`, and
/// driven by `SettingsWindow.applySearch`.
final class SettingsSearchHighlightTarget {
    private let matchRanges: (String) -> [Range<Int>]
    private let applyHighlight: ([Range<Int>]) -> Void
    private let clearHighlight: () -> Void

    init(_ matchRanges: @escaping (String) -> [Range<Int>], _ applyHighlight: @escaping ([Range<Int>]) -> Void, _ clearHighlight: @escaping () -> Void) {
        self.matchRanges = matchRanges
        self.applyHighlight = applyHighlight
        self.clearHighlight = clearHighlight
    }

    convenience init(_ hasMatch: @escaping (String) -> Bool, _ applyHighlight: @escaping () -> Void, _ clearHighlight: @escaping () -> Void) {
        self.init({ query in
            hasMatch(query) ? [0..<1] : []
        }, { _ in
            applyHighlight()
        }, clearHighlight)
    }

    func hasMatch(_ query: String) -> Bool {
        !matchRanges(query).isEmpty
    }

    func updateHighlight(_ query: String) {
        let ranges = matchRanges(query)
        if ranges.isEmpty {
            clearHighlight()
        } else {
            applyHighlight(ranges)
        }
    }

    func clear() {
        clearHighlight()
    }
}

/// Search-highlight factories + rendering for the *text label* controls (`NSTextField` and
/// `LightLabel`). Extracted from `SettingsWindow` so the row/label widgets that use them
/// (`TableGroupView.makeText`, `SidebarListRow`) don't transitively depend on the whole settings
/// window — which is what lets them be unit-tested in isolation.
///
/// The other `highlightTarget` overloads (popups, buttons, segmented controls, info popovers)
/// stay on `SettingsWindow`: their highlight is a `CAShapeLayer` pill keyed to the live sheet
/// windows the settings window manages, so they're genuinely coupled to it.
enum SettingsSearchHighlight {
    private static let roundedHighlightLayerName = "settingsSearchRoundedHighlight"
    private static let roundedHighlightCornerRadius = CGFloat(4)
    private static let roundedHighlightHorizontalInset = CGFloat(1.5)
    private static let roundedHighlightVerticalInset = CGFloat(0.8)
    private static let roundedHighlightLeadingTrim = CGFloat(1.4)

    static func highlightTarget(_ textField: NSTextField) -> SettingsSearchHighlightTarget? {
        guard !textField.stringValue.isEmpty else { return nil }
        // `attributedStringValue` takes precedence over the textField's `textColor` / `font` for
        // rendering. If we bake either into the attributed string at apply time, subsequent
        // changes to the textField's properties (e.g. a row selection toggle swapping textColor
        // white↔dark or font regular↔semibold) don't propagate to the displayed text.
        //
        // Strategy: only attach an attribute to the matched (highlighted) ranges. The rest of
        // the string has no foreground color and no font attribute, so AppKit's NSCell renders
        // those characters using the textField's own `textColor` and `font` — exactly the
        // properties `DynamicColorTextField` and `SidebarListRow.updateStyle` keep current.
        // The layout pass inside `applyRoundedHighlights` does need an explicit font to position
        // the yellow boxes accurately (NSLayoutManager defaults to plain system font otherwise),
        // so we hand it a separate "layout" attributed string with the current font filled in.
        // It only computes positions and never touches the textField, so no display freezing.
        var isHighlighted = false
        return SettingsSearchHighlightTarget({ query in
            SettingsSearch.match(query, in: textField.stringValue)?.ranges ?? []
        }, { ranges in
            let text = textField.stringValue
            let nsRanges = ranges.compactMap { characterRangeToNSRange($0, in: text) }
            let displayString = NSMutableAttributedString(string: text)
            nsRanges.forEach {
                displayString.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: $0)
            }
            textField.attributedStringValue = displayString
            let baseFont = textField.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let layoutString = NSMutableAttributedString(string: text, attributes: [.font: baseFont])
            nsRanges.forEach {
                layoutString.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: $0)
            }
            applyRoundedHighlights(to: textField, attributedString: layoutString, ranges: nsRanges)
            isHighlighted = true
        }, {
            guard isHighlighted else { return }
            // Self-assigning stringValue clears the cell's attributedStringValue and switches the
            // textField back to plain rendering driven by `textColor` + `font`.
            textField.stringValue = textField.stringValue
            clearRoundedHighlights(from: textField)
            isHighlighted = false
        })
    }

    /// `LightLabel` does its own draw via `NSAttributedString.draw(in:)`, so the search highlight
    /// is just a flag the label reads on its next draw pass — no `attributedStringValue` mutation,
    /// no `CAShapeLayer` overlay machinery (the label renders the yellow backgrounds inline).
    /// Selection-state changes that update `textColor` / `font` propagate naturally since the
    /// label re-evaluates its rendered attributed string on every redraw.
    static func highlightTarget(_ label: LightLabel) -> SettingsSearchHighlightTarget? {
        guard !label.stringValue.isEmpty else { return nil }
        var isHighlighted = false
        return SettingsSearchHighlightTarget({ query in
            SettingsSearch.match(query, in: label.stringValue)?.ranges ?? []
        }, { ranges in
            let text = label.stringValue
            let nsRanges = ranges.compactMap { characterRangeToNSRange($0, in: text) }
            label.applyHighlight(ranges: nsRanges, foregroundColor: Appearance.searchMatchForegroundColor)
            isHighlighted = true
        }, {
            guard isHighlighted else { return }
            label.clearHighlight()
            isHighlighted = false
        })
    }

    static func characterRangeToNSRange(_ range: Range<Int>, in text: String) -> NSRange? {
        if range.lowerBound < 0 || range.upperBound > text.count || range.isEmpty { return nil }
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(text.startIndex, offsetBy: range.upperBound)
        return NSRange(start..<end, in: text)
    }

    static func clearRoundedHighlights(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == roundedHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    static func applyRoundedHighlights(to textField: NSTextField,
                                       attributedString: NSAttributedString,
                                       ranges: [NSRange]) {
        clearRoundedHighlights(from: textField)
        guard !ranges.isEmpty else { return }
        textField.layoutSubtreeIfNeeded()
        let textRect = textDrawingRect(textField)
        guard textRect.width > 0, textRect.height > 0 else { return }
        textField.wantsLayer = true
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: textRect.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = textField.maximumNumberOfLines
        textContainer.lineBreakMode = textField.lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let horizontalOffset = textRect.minX
        let verticalOffset = textRect.minY + max(0, (textRect.height - usedRect.height) / 2)
        ranges.forEach { range in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                var highlightRect = rect.offsetBy(dx: horizontalOffset, dy: verticalOffset)
                highlightRect = highlightRect.insetBy(dx: -roundedHighlightHorizontalInset, dy: -roundedHighlightVerticalInset)
                highlightRect = leadingTrimmedHighlightRect(highlightRect, textField)
                let layer = noAnimation { CAShapeLayer() }
                layer.name = roundedHighlightLayerName
                layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
                layer.path = CGPath(roundedRect: highlightRect, cornerWidth: roundedHighlightCornerRadius, cornerHeight: roundedHighlightCornerRadius, transform: nil)
                textField.layer?.insertSublayer(layer, at: 0)
            }
        }
    }

    private static func leadingTrimmedHighlightRect(_ rect: CGRect, _ textField: NSTextField) -> CGRect {
        let trimmedWidth = max(rect.width - roundedHighlightLeadingTrim, 0.5)
        if textField.userInterfaceLayoutDirection == .rightToLeft {
            return CGRect(x: rect.minX, y: rect.minY, width: trimmedWidth, height: rect.height)
        }
        return CGRect(x: rect.minX + roundedHighlightLeadingTrim, y: rect.minY, width: trimmedWidth, height: rect.height)
    }

    private static func textDrawingRect(_ textField: NSTextField) -> CGRect {
        textField.cell?.drawingRect(forBounds: textField.bounds) ?? textField.bounds
    }
}
