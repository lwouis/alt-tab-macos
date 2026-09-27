import Cocoa

/// The before/after picture on a live permission card: two small scenes with a chevron between
/// them, showing what the grant changes. Drawn rather than shipped as assets so it follows the
/// accent color and both appearances, and so it costs nothing in the bundle.
///
/// Coordinates below read top-down (`isFlipped`), matching how the scenes were laid out.
class PermissionIllustrationView: NSView {
    enum Kind {
        /// Left: the window you picked is stuck behind another. Right: it came to the front.
        case accessibility
        /// Left: the switcher with empty placeholders. Right: the same cells filled with window pictures.
        case screenRecording
    }

    private static let sceneSize = NSSize(width: 148, height: 86)
    private static let sceneGap = CGFloat(12)
    private static let chevronWidth = CGFloat(10)
    private static let cornerRadius = CGFloat(8)
    /// Stand-ins for three arbitrary app windows. Mid-tone on purpose: they read the same in both
    /// appearances, and they are the only fixed colors here.
    private static let windowTints = [
        NSColor(srgbRed: 0.55, green: 0.70, blue: 0.88, alpha: 1),
        NSColor(srgbRed: 0.89, green: 0.62, blue: 0.58, alpha: 1),
        NSColor(srgbRed: 0.58, green: 0.80, blue: 0.65, alpha: 1),
    ]

    private let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let size = intrinsicContentSize
        fit(size.width, size.height)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        return NSSize(
            width: Self.sceneSize.width * 2 + Self.sceneGap * 2 + Self.chevronWidth,
            height: Self.sceneSize.height)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let before = NSRect(origin: .zero, size: Self.sceneSize)
        let after = before.offsetBy(dx: Self.sceneSize.width + Self.sceneGap * 2 + Self.chevronWidth, dy: 0)
        drawScene(before, granted: false)
        drawScene(after, granted: true)
        drawChevron(at: NSPoint(x: before.maxX + Self.sceneGap, y: before.midY))
    }

    private func drawScene(_ rect: NSRect, granted: Bool) {
        NSColor.underPageBackgroundColor.setFill()
        let background = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        background.fill()
        NSColor.separatorColor.setStroke()
        background.lineWidth = 1
        background.stroke()
        NSGraphicsContext.saveGraphicsState()
        background.setClip()
        switch kind {
            case .accessibility: drawFocusScene(rect, granted: granted)
            case .screenRecording: drawThumbnailsScene(rect, granted: granted)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Accessibility: the picked window comes forward

    private func drawFocusScene(_ rect: NSRect, granted: Bool) {
        let other = NSRect(x: rect.minX + 38, y: rect.minY + 24, width: 100, height: 56)
        let picked = granted
            ? NSRect(x: rect.minX + 16, y: rect.minY + 14, width: 102, height: 62)
            : NSRect(x: rect.minX + 9, y: rect.minY + 10, width: 84, height: 56)
        if granted {
            drawMiniWindow(other, picked: false)
            drawMiniWindow(picked, picked: true)
        } else {
            drawMiniWindow(picked, picked: true)
            drawMiniWindow(other, picked: false)
        }
    }

    private func drawMiniWindow(_ rect: NSRect, picked: Bool) {
        let titlebarHeight = CGFloat(9)
        let body = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.textBackgroundColor.setFill()
        body.fill()
        NSGraphicsContext.saveGraphicsState()
        body.setClip()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: titlebarHeight).fill()
        NSColor.tertiaryLabelColor.setFill()
        for index in 0..<3 {
            let dot = NSRect(x: rect.minX + 4 + CGFloat(index) * 5.5, y: rect.minY + titlebarHeight / 2 - 1.5, width: 3, height: 3)
            NSBezierPath(ovalIn: dot).fill()
        }
        NSColor.quaternaryLabelColor.setFill()
        for (index, width) in [rect.width * 0.6, rect.width * 0.42].enumerated() {
            let line = NSRect(x: rect.minX + 6, y: rect.minY + titlebarHeight + 5 + CGFloat(index) * 7, width: width, height: 3)
            NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        if picked {
            NSColor.controlAccentColor.setStroke()
            body.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            body.lineWidth = 1
        }
        body.stroke()
    }

    // MARK: - Screen Recording: placeholders become window pictures

    private func drawThumbnailsScene(_ rect: NSRect, granted: Bool) {
        let panel = NSRect(x: rect.minX + 7, y: rect.minY + 21, width: 134, height: 44)
        let panelPath = NSBezierPath(roundedRect: panel, xRadius: 9, yRadius: 9)
        NSColor.textBackgroundColor.setFill()
        panelPath.fill()
        NSColor.separatorColor.setStroke()
        panelPath.lineWidth = 1
        panelPath.stroke()
        for index in 0..<3 {
            let cell = NSRect(x: panel.minX + 5 + CGFloat(index) * 43, y: panel.minY + 5, width: 37, height: 34)
            if granted {
                drawThumbnail(cell, tint: Self.windowTints[index])
            } else {
                drawPlaceholder(cell)
            }
            guard index == 1 else { continue }
            NSColor.controlAccentColor.setStroke()
            let selection = NSBezierPath(roundedRect: cell.insetBy(dx: -1, dy: -1), xRadius: 5, yRadius: 5)
            selection.lineWidth = 2
            selection.stroke()
        }
    }

    private func drawPlaceholder(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.lineWidth = 1.5
        path.setLineDash([3, 2.5], count: 2, phase: 0)
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }

    private func drawThumbnail(_ rect: NSRect, tint: NSColor) {
        let titlebarHeight = CGFloat(7)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        path.setClip()
        tint.setFill()
        rect.fill()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: titlebarHeight).fill()
        NSColor.tertiaryLabelColor.setFill()
        for index in 0..<3 {
            let dot = NSRect(x: rect.minX + 3 + CGFloat(index) * 4, y: rect.minY + titlebarHeight / 2 - 1, width: 2, height: 2)
            NSBezierPath(ovalIn: dot).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - The arrow between the two scenes

    private func drawChevron(at center: NSPoint) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x - 2, y: center.y - 5))
        path.line(to: NSPoint(x: center.x + 3, y: center.y))
        path.line(to: NSPoint(x: center.x - 2, y: center.y + 5))
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }
}
