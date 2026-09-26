import Cocoa

final class SearchDiscoveryPanel: NSPanel {
    static let message = NSLocalizedString("Press %@ to search your windows.", comment: "Window search hint; placeholder is the configured keyboard shortcut")
    static let dismissLabel = NSLocalizedString("Don't show this search hint again", comment: "")
    let hintLabel = NSTextField(wrappingLabelWithString: "")
    let dismissButton = SearchDiscoveryCloseButton()
    private(set) var background = NSView()
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
        animationBehavior = .none
        collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
        setAccessibilitySubrole(.unknown)
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.isSelectable = false
        hintLabel.maximumNumberOfLines = 0
        hintLabel.lineBreakMode = .byWordWrapping
        dismissButton.isBordered = false
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        dismissButton.imageScaling = .scaleProportionallyDown
        dismissButton.toolTip = Self.dismissLabel
        dismissButton.setAccessibilityLabel(Self.dismissLabel)
        dismissButton.target = self
        dismissButton.action = #selector(dismissHint)
        setBackground(background, host: background)
    }

    /// `host` is where the content goes: the view itself, or a Liquid Glass view's `contentView`.
    func setBackground(_ view: NSView, host: NSView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        host.addSubview(hintLabel)
        host.addSubview(dismissButton)
        background = view
        self.host = host
        contentView = view
    }

    /// `maxCornerRadius` is capped at half the height, so a one-line hint is a capsule.
    func prepare(shortcut: String, spokenShortcut: String, dark: Bool, highContrast: Bool, maxWidth: CGFloat,
                 maxCornerRadius: CGFloat = .greatestFiniteMagnitude) -> NSSize {
        appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
        let text = NSMutableAttributedString(string: String(format: Self.message, "\u{FFFC}"),
                                             attributes: [.font: hintLabel.font!, .foregroundColor: dark ? NSColor.white : NSColor.black])
        let attachment = NSTextAttachment()
        attachment.attachmentCell = SearchDiscoveryKeycapCell(imageCell: Self.keycap(shortcut, dark: dark, highContrast: highContrast))
        text.replaceCharacters(in: (text.string as NSString).range(of: "\u{FFFC}"), with: NSAttributedString(attachment: attachment))
        hintLabel.attributedStringValue = text
        hintLabel.setAccessibilityLabel(String(format: Self.message, spokenShortcut))
        let width = max(1, min(470, maxWidth))
        let textWidth = max(1, width - 64)
        let textHeight = ceil(text.boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
        let size = NSSize(width: width, height: max(44, textHeight + 16))
        background.frame.size = size
        if host !== background { host.frame = NSRect(origin: .zero, size: size) }
        cornerRadius = min(maxCornerRadius, size.height / 2)
        hintLabel.frame = NSRect(x: 16, y: (size.height - textHeight) / 2, width: textWidth, height: textHeight)
        dismissButton.frame = NSRect(x: width - 36, y: (size.height - 24) / 2, width: 24, height: 24)
        hintLabel.textColor = dark ? .white : .black
        dismissButton.dark = dark
        // The switcher has no outline; this one only exists for increased contrast.
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.borderColor = NSColor(calibratedWhite: dark ? 0.55 : 0.45, alpha: 1).cgColor
        background.layer?.borderWidth = highContrast ? 2 : 0
        return size
    }

    override func orderOut(_ sender: Any?) {
        // hidden under the pointer, the button never gets its mouseExited
        dismissButton.isHovered = false
        super.orderOut(sender)
    }

    @objc private func dismissHint() { onDismiss?() }

    private static func keycap(_ shortcut: String, dark: Bool, highContrast: Bool) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: dark ? NSColor.white : NSColor.black]
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // AltTab is usually not the active app while the switcher shows
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private func updateHoverStyle() {
        wantsLayer = true
        layer?.cornerRadius = bounds.height / 2
        layer?.backgroundColor = isHovered ? NSColor(calibratedWhite: dark ? 1 : 0, alpha: dark ? 0.18 : 0.1).cgColor : nil
        contentTintColor = dark ? (isHovered ? .white : NSColor(calibratedWhite: 1, alpha: 0.7)) : (isHovered ? .black : .darkGray)
    }
}
