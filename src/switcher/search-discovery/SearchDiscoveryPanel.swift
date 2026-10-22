import Cocoa

final class SearchDiscoveryPanel: NSPanel {
    static let message = NSLocalizedString(
        "Press %@",
        comment: "Window search hint; placeholder is the configured keyboard shortcut"
    )
    static let dismissLabel = NSLocalizedString("Don't show discovery tips again", comment: "")
    let titleLabel = NSTextField(labelWithString: "")
    private let rabbit = ProMascotView()
    private let root = NSView()
    let hintLabel = NSTextField(labelWithString: "")
    let dismissButton = SearchDiscoveryCloseButton()
    private(set) var background: NSView = SpeechBubbleView()
    private var host: NSView
    private(set) var cornerRadius = CGFloat(0)
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        host = background
        super.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // unlike the switcher, the rabbit and its bubble keep their shadow with every appearance
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        setAccessibilitySubrole(.unknown)
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.isSelectable = false
        for label in [titleLabel, hintLabel] {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.cell?.usesSingleLineMode = true
        }
        // The single-line cell fast path ignores attachment height when placing the baseline.
        // maximumNumberOfLines still keeps the instruction on one line.
        hintLabel.cell?.usesSingleLineMode = false
        dismissButton.isBordered = false
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        dismissButton.imageScaling = .scaleProportionallyDown
        dismissButton.toolTip = Self.dismissLabel
        dismissButton.setAccessibilityLabel(Self.dismissLabel)
        dismissButton.target = self
        dismissButton.action = #selector(dismissHint)
        setBackground(background, host: background)
    }

    /// `host` is where the content goes: the view itself, or a Liquid Glass view's `contentView`.
    func setBackground(_ view: NSView, host: NSView) {
        background.removeFromSuperview()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        root.addSubview(view)
        root.addSubview(rabbit)
        host.addSubview(titleLabel)
        host.addSubview(hintLabel)
        host.addSubview(dismissButton)
        background = view
        self.host = host
        contentView = root
    }

    func setMaterial(_ view: NSView) {
        (background as? SpeechBubbleView)?.setMaterial(view)
    }

    /// The width hugs the measured text, up to the available screen width and the shared cap.
    func prepare(shortcut: String, spokenShortcut: String, dark: Bool, highContrast: Bool, maxWidth: CGFloat,
        title: String? = nil,
        instruction: String? = nil,
        holdKey: (label: String, spoken: String)? = nil
    ) -> NSSize {
        appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
        let rtl = root.userInterfaceLayoutDirection == .rightToLeft
        titleLabel.stringValue = title ?? NSLocalizedString("Find a window by typing", comment: "")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = rtl ? .right : .left
        hintLabel.alignment = rtl ? .right : .left
        titleLabel.textColor = dark ? .white : .black
        let message = instruction ?? Self.message
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rtl ? .right : .left
        paragraph.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        paragraph.lineBreakMode = .byTruncatingTail
        // Format arguments follow the instruction's placeholders: the hold modifiers first when there are any.
        let keys: [(label: String, spoken: String)] = (holdKey.map { [$0] } ?? []) + [(shortcut, spokenShortcut)]
        let markers = ["\u{E000}", "\u{E001}"]
        let text = NSMutableAttributedString(string: String(format: message, markers[0], markers[1]),
            attributes: [.font: hintLabel.font!, .foregroundColor: dark ? NSColor.white : NSColor.black,
                         .paragraphStyle: paragraph])
        for (key, marker) in zip(keys, markers) {
            let range = (text.string as NSString).range(of: marker)
            guard range.location != NSNotFound else { continue }
            let attachment = NSTextAttachment()
            attachment.attachmentCell = SearchDiscoveryKeycapCell(imageCell: Self.keycap(key.label, dark: dark, highContrast: highContrast))
            text.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
        }
        hintLabel.attributedStringValue = text
        hintLabel.setAccessibilityLabel(String(format: message, keys[0].spoken, keys.count > 1 ? keys[1].spoken : ""))
        let titleWidth = ceil(titleLabel.cell!.cellSize.width)
        let naturalTextWidth = hintLabel.cell!.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: 10000, height: 10000)).width
        let bubbleInsets = SpeechBubbleView.contentInsets(pointsRight: rtl)
        let horizontalInsets = bubbleInsets.left + bubbleInsets.right
        let width = max(1, min(560, maxWidth, ceil(max(titleWidth + 32, naturalTextWidth)) + 88 + horizontalInsets))
        let textWidth = max(1, width - 88 - horizontalInsets)
        let measurement = NSRect(x: 0, y: 0, width: textWidth, height: 10000)
        let textHeight = max(24, ceil(hintLabel.cell!.cellSize(forBounds: measurement).height))
        let titleHeight = ceil(titleLabel.intrinsicContentSize.height)
        let contentHeight = titleHeight + SpeechBubbleView.lineSpacing + textHeight
        let size = NSSize(width: width, height: contentHeight + bubbleInsets.top + bubbleInsets.bottom)
        root.frame.size = size
        (background as? SpeechBubbleView)?.pointsRight = rtl
        background.frame = NSRect(x: rtl ? 0 : 88, y: 0, width: width - 88, height: size.height)
        if host !== background { host.frame = NSRect(origin: .zero, size: background.frame.size) }
        rabbit.frame = NSRect(x: rtl ? width - 76 : 0, y: (size.height - 76) / 2, width: 76, height: 76)
        cornerRadius = SpeechBubbleView.cornerRadius
        let content = SpeechBubbleView.contentRect(in: background.bounds, pointsRight: rtl)
        titleLabel.frame = titleLabel.frame(forAlignmentRect: NSRect(x: content.minX + (rtl ? 32 : 0),
            y: content.maxY - titleHeight, width: max(1, textWidth - 32), height: titleHeight))
        hintLabel.frame = hintLabel.frame(forAlignmentRect:
            NSRect(x: content.minX, y: content.minY, width: textWidth, height: textHeight))
        dismissButton.frame = NSRect(x: rtl ? content.minX : content.maxX - 24,
            y: titleLabel.frame.midY - 12, width: 24, height: 24)
        hintLabel.textColor = dark ? .white : .black
        dismissButton.dark = dark
        // The switcher has no outline; this one only exists for increased contrast.
        background.wantsLayer = true
        background.layer?.cornerRadius = 0
        background.needsDisplay = true
        (background as? SpeechBubbleView)?.highContrast = highContrast
        background.layer?.borderWidth = background is SpeechBubbleView ? 0 : highContrast ? 2 : 0
        return size
    }

    override func orderOut(_ sender: Any?) {
        // hidden under the pointer, the button never gets its mouseExited
        dismissButton.isHovered = false
        super.orderOut(sender)
    }

    @objc private func dismissHint() { onDismiss?() }

    static func keycap(_ shortcut: String, dark: Bool, highContrast: Bool) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: dark ? NSColor.white : NSColor.black,
        ]
        let label = NSAttributedString(string: shortcut, attributes: attributes)
        let size = NSSize(width: max(24, ceil(label.size().width) + 12), height: 24)
        return NSImage(size: size, flipped: false) { _ in
            // a thin outline, and a slightly thicker edge at the bottom to lift the key
            let faceFrame = NSRect(x: 1.5, y: 2.5, width: size.width - 3, height: size.height - 4)
            let shadow = NSBezierPath(roundedRect: faceFrame.offsetBy(dx: 0, dy: -1.5), xRadius: 5, yRadius: 5)
            NSColor(calibratedWhite: 0, alpha: dark ? 0.5 : 0.28).setFill()
            shadow.fill()
            let face = NSBezierPath(roundedRect: faceFrame, xRadius: 5, yRadius: 5)
            NSColor(calibratedWhite: dark ? 0.32 : 1, alpha: 1).setFill()
            face.fill()
            NSColor(calibratedWhite: dark ? (highContrast ? 1 : 0.42) : (highContrast ? 0 : 0.8), alpha: 1).setStroke()
            face.lineWidth = highContrast ? 1.5 : 0.75
            face.stroke()
            label.draw(at: NSPoint(x: (size.width - label.size().width) / 2, y: floor(faceFrame.midY - label.size().height / 2)))
            return true
        }
    }
}

final class SearchDiscoveryKeycapCell: NSTextAttachmentCell {
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -6) }
    override func wantsToTrackMouse() -> Bool { false }
}

final class SearchDiscoveryCloseButton: NSButton {
    private var hoverArea: NSTrackingArea?
    var dark = false { didSet { updateHoverStyle() } }
    var isHovered = false { didSet { updateHoverStyle() } }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // AltTab is usually not the active app while the switcher shows
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with _: NSEvent) { isHovered = true }
    override func mouseExited(with _: NSEvent) { isHovered = false }

    private func updateHoverStyle() {
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = isHovered ? NSColor(calibratedWhite: dark ? 1 : 0, alpha: 0.18).cgColor : nil
        contentTintColor = dark ? (isHovered ? .white : NSColor(calibratedWhite: 1, alpha: 0.7)) : (isHovered ? .black : .darkGray)
    }
}

final class ProMascotView: NSImageView {
    private static let artwork = NSImage(named: "pro-rabbit")

    init() {
        super.init(frame: .zero)
        image = Self.artwork
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}

final class MascotMessageView: NSStackView {
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")

    init(title: String, message: String, emphasizeMessage: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let rabbit = ProMascotView()
        rabbit.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        rabbit.shadow = shadow
        rabbit.translatesAutoresizingMaskIntoConstraints = false
        rabbit.widthAnchor.constraint(equalToConstant: 76).isActive = true
        rabbit.heightAnchor.constraint(equalToConstant: 76).isActive = true
        heading.font = .systemFont(ofSize: emphasizeMessage ? 13 : 18, weight: emphasizeMessage ? .regular : .semibold)
        heading.textColor = emphasizeMessage ? .secondaryLabelColor : .labelColor
        detail.font = .systemFont(ofSize: emphasizeMessage ? 20 : 13, weight: emphasizeMessage ? .bold : .regular)
        detail.textColor = emphasizeMessage ? .labelColor : .secondaryLabelColor
        heading.isSelectable = false
        detail.isSelectable = false
        update(title: title, message: message)
        let bubble = NSStackView(views: [heading, detail])
        bubble.orientation = .vertical
        bubble.alignment = .leading
        bubble.spacing = SpeechBubbleView.lineSpacing
        let balloon = SpeechBubbleView()
        balloon.pointsRight = userInterfaceLayoutDirection == .rightToLeft
        balloon.translatesAutoresizingMaskIntoConstraints = false
        balloon.addContent(bubble)
        addArrangedSubview(rabbit)
        addArrangedSubview(balloon)
        spacing = 10
    }

    func update(title: String, message: String, proGradient: Bool = false) {
        heading.stringValue = title
        detail.stringValue = message
        detail.setAccessibilityLabel(message)
        guard proGradient, let range = message.range(of: ProBadgeView.proLabel) else { return }
        let text = NSMutableAttributedString(string: message,
            attributes: [.font: detail.font!, .foregroundColor: detail.textColor!])
        text.replaceCharacters(in: NSRange(range, in: message),
            with: ProGradient.makeProTextAttachment(font: detail.font!))
        detail.attributedStringValue = text
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}

final class SpeechBubbleView: NSView {
    static let cornerRadius = CGFloat(24)
    static let contentPadding = CGFloat(18)
    static let lineSpacing = CGFloat(4)
    private static let tailWidth = CGFloat(10)
    private static let outlineInset = CGFloat(1)
    var pointsRight = false { didSet { needsLayout = true } }
    var highContrast = false { didSet { needsLayout = true } }
    private var material: NSView?
    private let outline = CAShapeLayer()

    static func contentInsets(pointsRight: Bool) -> NSEdgeInsets {
        let inset = outlineInset + contentPadding
        return NSEdgeInsets(top: inset, left: inset + (pointsRight ? 0 : tailWidth),
            bottom: inset, right: inset + (pointsRight ? tailWidth : 0))
    }

    static func contentRect(in bounds: NSRect, pointsRight: Bool) -> NSRect {
        let insets = contentInsets(pointsRight: pointsRight)
        return NSRect(x: bounds.minX + insets.left, y: bounds.minY + insets.bottom,
            width: max(1, bounds.width - insets.left - insets.right),
            height: max(1, bounds.height - insets.top - insets.bottom))
    }

    func addContent(_ view: NSView) {
        let insets = Self.contentInsets(pointsRight: pointsRight)
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: leftAnchor, constant: insets.left),
            view.rightAnchor.constraint(equalTo: rightAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    func setMaterial(_ view: NSView) {
        material?.removeFromSuperview()
        material = view
        addSubview(view, positioned: .below, relativeTo: subviews.first)
        wantsLayer = true
        layer?.addSublayer(outline)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        material?.frame = bounds
        let path = bubblePath()
        let shape = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<path.elementCount {
            switch path.element(at: index, associatedPoints: &points) {
            case .moveTo: shape.move(to: points[0])
            case .lineTo: shape.addLine(to: points[0])
            case .cubicCurveTo: shape.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: shape.addQuadCurve(to: points[1], control: points[0])
            case .closePath: shape.closeSubpath()
            @unknown default: break
            }
        }
        let mask = CAShapeLayer()
        mask.path = shape
        material?.wantsLayer = true
        material?.layer?.mask = mask
        outline.path = shape
        outline.fillColor = nil
        outline.strokeColor = highContrast ? NSColor.labelColor.cgColor : nil
        outline.lineWidth = 2
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        guard material == nil else { return }
        let path = bubblePath()
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (highContrast ? NSColor.labelColor : NSColor.separatorColor).setStroke()
        path.lineWidth = highContrast ? 2 : 1
        path.stroke()
    }

    /// One closed silhouette, with no edge crossing the mouth of the tail.
    func bubblePath() -> NSBezierPath {
        let r = bounds.insetBy(dx: Self.outlineInset, dy: Self.outlineInset)
        let left = r.minX + Self.tailWidth
        let radius = max(0, min(Self.cornerRadius, (r.height - 20) / 2))
        let arc = radius * 0.5522847498
        let p = NSBezierPath()
        p.move(to: NSPoint(x: left + radius, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        p.curve(to: NSPoint(x: r.maxX, y: r.minY + radius),
            controlPoint1: NSPoint(x: r.maxX - radius + arc, y: r.minY),
            controlPoint2: NSPoint(x: r.maxX, y: r.minY + radius - arc))
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        p.curve(to: NSPoint(x: r.maxX - radius, y: r.maxY),
            controlPoint1: NSPoint(x: r.maxX, y: r.maxY - radius + arc),
            controlPoint2: NSPoint(x: r.maxX - radius + arc, y: r.maxY))
        p.line(to: NSPoint(x: left + radius, y: r.maxY))
        p.curve(to: NSPoint(x: left, y: r.maxY - radius),
            controlPoint1: NSPoint(x: left + radius - arc, y: r.maxY),
            controlPoint2: NSPoint(x: left, y: r.maxY - radius + arc))
        p.line(to: NSPoint(x: left, y: r.midY + 8))
        p.line(to: NSPoint(x: r.minX, y: r.midY))
        p.line(to: NSPoint(x: left, y: r.midY - 8))
        p.line(to: NSPoint(x: left, y: r.minY + radius))
        p.curve(to: NSPoint(x: left + radius, y: r.minY),
            controlPoint1: NSPoint(x: left, y: r.minY + radius - arc),
            controlPoint2: NSPoint(x: left + radius - arc, y: r.minY))
        p.close()
        if pointsRight {
            p.transform(using: AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: bounds.width, tY: 0))
        }
        return p
    }
}
