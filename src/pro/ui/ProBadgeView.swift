import Cocoa

enum ProGradient {
    static let colors: [CGColor] = [
        NSColor(red: 0xFF / 255.0, green: 0x44 / 255.0, blue: 0x88 / 255.0, alpha: 1).cgColor,
        NSColor(red: 0x44 / 255.0, green: 0x88 / 255.0, blue: 0xFF / 255.0, alpha: 1).cgColor,
        NSColor(red: 0x66 / 255.0, green: 0xCC / 255.0, blue: 0xFF / 255.0, alpha: 1).cgColor,
    ]
    static let locations: [NSNumber] = [0.0, 0.5, 1.0]
    // 36° CCW from horizontal → direction (cos36°, sin36°) ≈ (0.809, 0.588)
    static let startPoint = CGPoint(x: 0.5 - 0.5 * 0.809, y: 0.5 - 0.5 * 0.588)
    static let endPoint = CGPoint(x: 0.5 + 0.5 * 0.809, y: 0.5 + 0.5 * 0.588)
    static let representativeColor = NSColor(red: 0xFF / 255.0, green: 0x44 / 255.0, blue: 0x88 / 255.0, alpha: 1)
    private static let shineAnimationKey = "shine"
    #if DEBUG
    static var animationsDisabledForQa = false
    #endif

    static func makeLayer(alpha: CGFloat = 1, flipped: Bool = false) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.colors = alpha == 1 ? colors : colors.map { $0.copy(alpha: alpha)! }
        g.locations = locations
        setEndpoints(on: g, flipped: flipped)
        return g
    }

    /// A white highlight that sweeps once across `layer`, left to right, then removes itself. A
    /// call landing while a sweep is still running is dropped: the running sweep's own sublayer is
    /// the "already shining" flag, so no caller has to keep one.
    static func playShine(over layer: CALayer) {
        #if DEBUG
        guard !animationsDisabledForQa else { return }
        #endif
        guard layer.sublayers?.contains(where: { $0.animation(forKey: shineAnimationKey) != nil }) != true else { return }
        let size = layer.bounds.size
        let shine = CAGradientLayer()
        shine.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.3).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        shine.locations = [0, 0.5, 1]
        shine.startPoint = CGPoint(x: 0, y: 0.5)
        shine.endPoint = CGPoint(x: 1, y: 0.5)
        shine.frame = CGRect(x: -size.width, y: 0, width: size.width, height: size.height)
        layer.addSublayer(shine)
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -size.width / 2
        animation.toValue = size.width + size.width / 2
        animation.duration = 0.6
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { shine.removeFromSuperlayer() }
        shine.add(animation, forKey: shineAnimationKey)
        CATransaction.commit()
    }

    static func setEndpoints(on layer: CAGradientLayer, flipped: Bool) {
        if flipped {
            layer.startPoint = CGPoint(x: startPoint.x, y: 1 - startPoint.y)
            layer.endPoint = CGPoint(x: endPoint.x, y: 1 - endPoint.y)
        } else {
            layer.startPoint = startPoint
            layer.endPoint = endPoint
        }
    }

    static func makeGradientTextImage(_ string: String, font: NSFont) -> NSImage {
        let text = NSAttributedString(string: string, attributes: [.font: font])
        let measured = text.size()
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        return NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            let line = CTLineCreateWithAttributedString(text as CFAttributedString)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            ctx.textPosition = CGPoint(x: 0, y: descent)
            ctx.setTextDrawingMode(.clip)
            CTLineDraw(line, ctx)
            let cs = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: [0, 0.5, 1]) {
                let start = CGPoint(x: size.width * startPoint.x, y: size.height * startPoint.y)
                let end = CGPoint(x: size.width * endPoint.x, y: size.height * endPoint.y)
                ctx.drawLinearGradient(gradient, start: start, end: end,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            ctx.restoreGState()
            return true
        }
    }

    static func makeProTextAttachment(font: NSFont, baselineOffset: CGFloat = 0) -> NSAttributedString {
        return makeGradientTextAttachment(ProBadgeView.proLabel, font: font, baselineOffset: baselineOffset)
    }

    /// Render any string as a gradient `NSImage` wrapped in an `NSTextAttachment`, ready to be
    /// concatenated into an `NSAttributedString`. Generalises `makeProTextAttachment` for callers
    /// that need the full gradient on a longer phrase (e.g. menu rows showing "Get Pro").
    static func makeGradientTextAttachment(_ string: String, font: NSFont, baselineOffset: CGFloat = 0) -> NSAttributedString {
        let image = makeGradientTextImage(string, font: font)
        let text = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(text as CFAttributedString)
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, nil, &descent, nil)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -descent, width: image.size.width, height: image.size.height)
        let result = NSMutableAttributedString(attachment: attachment)
        if baselineOffset != 0 {
            result.addAttribute(.baselineOffset, value: baselineOffset, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}

// Borderless button for actions we want to discourage: small, gray text, no underline.
class NotAdvisedButton: NSButton {
    convenience init(_ title: String) {
        self.init(title: title, target: nil, action: nil)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 11),
        ])
    }
}

/// `NSImageView` equivalent of `DynamicColorTextField` — recomputes `contentTintColor` on draw
/// using a closure. Used by the Pro-badge segment overlay to track AppKit's state-aware text
/// color across selection / key-window / appearance changes.
class DynamicColorImageView: NSImageView {
    var colorProvider: (() -> NSColor)?
    override func viewWillDraw() {
        super.viewWillDraw()
        if let newColor = colorProvider?(), contentTintColor != newColor {
            contentTintColor = newColor
        }
    }
}

class ProBadgeView: NSView {
    /// Inset between the badge and the segmented control's trailing edge.
    static let segmentTrailingPadding: CGFloat = 4

    /// The literal text rendered on the badge. Exposed as a constant so the search index can
    /// reference the same string (e.g. `ShortcutsWhenActiveSheet.searchableStrings`) without
    /// duplicating the `NSLocalizedString` call.
    static let proLabel = NSLocalizedString("Pro", comment: "")

    /// Bundle returned from `attach(to:segmentIndex:)`: the badge plus the icon and label
    /// overlays we render on top of the Pro segment. Callers store this to drive
    /// `refreshSelection` after click / window-key / Pro-lock transitions.
    struct SegmentOverlay {
        let badge: ProBadgeView
        let icon: NSImageView
        let label: NSTextField
    }

    /// Mirror AppKit's segmented-cell text rendering on a custom overlay label/icon. The system
    /// colors here are the same ones `NSSegmentedCell` picks internally:
    ///   - selected + key window  → `.alternateSelectedControlTextColor` (white on blue)
    ///   - everything else        → `.controlTextColor` (dark on light; AppKit auto-fades in
    ///     dark mode / disabled / inactive-window states)
    /// We don't hard-code RGB anywhere — we hand AppKit the same semantic tokens it'd pick on
    /// its own. The closure is re-evaluated on every `viewWillDraw` (see `DynamicColorTextField`
    /// / `DynamicColorImageView`), so a single `needsDisplay = true` after a selection or key
    /// change resyncs the color in all combinations.
    static func segmentColorProvider(for segmentedControl: NSSegmentedControl, segmentIndex: Int) -> () -> NSColor {
        return { [weak segmentedControl] in
            guard let seg = segmentedControl else { return .controlTextColor }
            let isSelected = seg.selectedSegment == segmentIndex
            let isKey = seg.window?.isKeyWindow ?? false
            return (isSelected && isKey) ? .alternateSelectedControlTextColor : .controlTextColor
        }
    }

    /// Overlay a Pro badge at the trailing edge of `segmentIndex`. Clears AppKit's native
    /// label/image for that segment and re-renders them through custom subviews so we can
    /// control truncation (badge must always fit; label truncates first) while keeping all
    /// other segments at their original width. Colors are still AppKit-resolved system tokens
    /// — see `segmentColorProvider` for the contract.
    /// Only valid for the LAST segment — the badge anchors to the control's trailing edge.
    @discardableResult
    static func attach(to segmentedControl: NSSegmentedControl, segmentIndex: Int, label: String, symbol: Symbols) -> SegmentOverlay {
        let selected = segmentedControl.selectedSegment == segmentIndex
        segmentedControl.setLabel("", forSegment: segmentIndex)
        segmentedControl.setImage(nil, forSegment: segmentIndex)
        segmentedControl.setToolTip(label, forSegment: segmentIndex)
        let segmentLeading = (0..<segmentIndex).reduce(CGFloat(0)) { $0 + segmentedControl.width(forSegment: $1) }
        let colorProvider = segmentColorProvider(for: segmentedControl, segmentIndex: segmentIndex)
        let iconView = DynamicColorImageView()
        iconView.colorProvider = colorProvider
        iconView.translatesAutoresizingMaskIntoConstraints = false
        // Rendered from our bundled font subset; `isTemplate = true` (set by NSImage.fromSymbol)
        // makes AppKit apply `contentTintColor`. Mirrors the sibling segments' native rendering.
        iconView.image = NSImage.fromSymbol(symbol, pointSize: 13)
        iconView.contentTintColor = colorProvider()
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        let textLabel = DynamicColorTextField(labelWithString: label)
        textLabel.colorProvider = colorProvider
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = segmentedControl.font
        textLabel.textColor = colorProvider()
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let badge = ProBadgeView()
        badge.setSelected(selected)
        segmentedControl.addSubview(iconView)
        segmentedControl.addSubview(textLabel)
        segmentedControl.addSubview(badge)
        let segmentWidth = segmentedControl.width(forSegment: segmentIndex)
        let iconWidth = iconView.fittingSize.width
        let textWidth = textLabel.fittingSize.width
        let badgeWidth = badge.fittingSize.width
        let contentWidth = iconWidth + 2 + textWidth
        let availableWidth = segmentWidth - badgeWidth - 4 - 4 - 4 // leading pad, gap, trailing pad
        // Position content as close to centered as possible without overlapping the Pro badge:
        // 1) Full-segment center if the centered content clears the badge.
        // 2) Otherwise shift left only as much as needed to keep the content's right edge clear.
        // 3) If even the leftmost position overflows, stay at the left pad and let the trailing
        //    constraint truncate.
        let maxContentRightEdge = segmentWidth - badgeWidth - 4
        let centerOffset = (segmentWidth - contentWidth) / 2
        let leadingOffset: CGFloat
        if centerOffset + contentWidth <= maxContentRightEdge {
            leadingOffset = segmentLeading + centerOffset
        } else {
            leadingOffset = segmentLeading + max(maxContentRightEdge - contentWidth, 8)
        }
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: segmentedControl.leadingAnchor, constant: leadingOffset),
            iconView.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor),
            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 2),
            textLabel.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor),
            textLabel.widthAnchor.constraint(lessThanOrEqualToConstant: availableWidth - iconWidth - 2),
            badge.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: segmentedControl.trailingAnchor, constant: -segmentTrailingPadding),
        ])
        return SegmentOverlay(badge: badge, icon: iconView, label: textLabel)
    }

    /// Sync the overlay's selection-dependent visuals to the segment's current selection. The
    /// badge flips between gradient (unselected) and white-overlay (selected + key); the icon
    /// and label redraw so their `colorProvider`-driven `viewWillDraw` picks up the new state.
    static func refreshSelection(in segmentedControl: NSSegmentedControl, proIndex: Int, overlay: SegmentOverlay) {
        overlay.badge.setSelected(segmentedControl.selectedSegment == proIndex)
        overlay.icon.needsDisplay = true
        overlay.label.needsDisplay = true
    }

    private let label = NSTextField(labelWithString: ProBadgeView.proLabel)
    private let fillGradient = ProGradient.makeLayer(alpha: 0.1)
    private let borderGradient = ProGradient.makeLayer(alpha: 0.7)
    private let textGradient = ProGradient.makeLayer(alpha: 1)
    private let borderMask = CAShapeLayer()
    private let textMask = CATextLayer()
    private(set) var isSelectedState = false
    private var windowObservers = [NSObjectProtocol]()
    var onWindowKeyChanged: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Register the "Pro" tag with the search index if a section build is in progress —
        // mirrors what the post-construction walk in `SettingsWindow.collectSearchContent` does
        // when it spots a `ProBadgeView`, just without needing the walk to find it after.
        SettingsSearchIndex.registerString(ProBadgeView.proLabel)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.alphaValue = 0
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        fillGradient.cornerRadius = 4
        borderMask.fillColor = NSColor.clear.cgColor
        borderMask.strokeColor = NSColor.white.cgColor
        borderMask.lineWidth = 1
        borderGradient.mask = borderMask
        textMask.string = ProBadgeView.proLabel
        textMask.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        textMask.fontSize = 9
        textMask.foregroundColor = NSColor.white.cgColor
        textMask.alignmentMode = .center
        textMask.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textGradient.mask = textMask
        layer?.addSublayer(fillGradient)
        layer?.addSublayer(borderGradient)
        layer?.addSublayer(textGradient)
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// The badge is a decoration on top of an interactive parent (style tile, segmented control,
    /// menu item). Returning `nil` lets clicks reach the parent so e.g. clicking the badge over the
    /// "Auto" segment or the "App Icons" style tile activates that segment / style.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        caTransaction {
            let b = bounds
            fillGradient.frame = b
            borderGradient.frame = b
            borderMask.frame = b
            borderMask.path = CGPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            textGradient.frame = b
            let labelFrame = label.frame
            textMask.frame = labelFrame.isEmpty ? b : labelFrame
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers = observeWindowKeyChanges(replacing: windowObservers) { [weak self] in self?.updateColors() }
        // Resync colors + force a layout pass for the current key state. This matters when the
        // badge is built lazily (e.g. the per-shortcut Appearance pane's `Size` Pro segment,
        // created when the user clicks the Appearance tab while Settings is already key) —
        // `init` ran with `window=nil`, so `updateColors` picked the not-key branch, and the
        // `didBecomeKey` observer never fires because there's no actual state change. Without
        // this nudge the badge's `layout()` may not run before the first display, leaving the
        // `borderMask.path` and `textMask.frame` unset and only the 10%-alpha fill layer visible
        // — i.e. the "faded" badge regression.
        updateColors()
        needsLayout = true
    }

    func setSelected(_ selected: Bool) {
        guard isSelectedState != selected else { return }
        isSelectedState = selected
        updateColors()
    }

    private var isWindowKey: Bool { window?.isKeyWindow ?? false }

    private func updateColors() {
        onWindowKeyChanged?()
        caTransaction {
            if isSelectedState && isWindowKey {
                let white = NSColor.white
                layer?.borderWidth = 1
                layer?.borderColor = white.withAlphaComponent(0.5).cgColor
                layer?.backgroundColor = white.withAlphaComponent(0.15).cgColor
                fillGradient.isHidden = true
                borderGradient.isHidden = true
                textGradient.isHidden = true
                label.textColor = white.withAlphaComponent(0.97)
                label.alphaValue = 1
            } else {
                layer?.borderWidth = 0
                layer?.borderColor = nil
                layer?.backgroundColor = nil
                fillGradient.isHidden = false
                borderGradient.isHidden = false
                textGradient.isHidden = false
                label.alphaValue = 0
            }
        }
    }
}
