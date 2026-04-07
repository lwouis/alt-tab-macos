import Cocoa

class WindowHighlightPanel: NSPanel {
    static var shared: WindowHighlightPanel!
    static let borderWidth = CGFloat(4)
    static let cornerRadius = CGFloat(10)

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        contentView = HighlightBorderView()
        collectionBehavior = .canJoinAllSpaces
        setAccessibilitySubrole(.unknown)
        Self.shared = self
    }

    static func show(_ position: CGPoint, _ size: CGSize) {
        var frame = NSRect(origin: position, size: size)
        frame.origin.y = NSScreen.screens.first!.frame.maxY - frame.maxY
        Self.shared.setFrame(frame, display: true)
        Self.shared.order(.below, relativeTo: TilesPanel.shared.windowNumber)
        Self.shared.level = NSWindow.Level(rawValue: TilesPanel.shared.level.rawValue - 1)
    }

    static func updateHighlightIfNeeded() {
        guard App.appIsBeingUsed && Preferences.highlightSelectedWindow && TilesPanel.shared.isKeyWindow,
              let window = Windows.selectedWindow(),
              !window.isWindowlessApp,
              let position = window.position,
              let size = window.size,
              !window.isMinimized else {
            Self.shared?.orderOut(nil)
            return
        }
        show(position, size)
    }
}

private class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        let borderWidth = WindowHighlightPanel.borderWidth
        let cornerRadius = WindowHighlightPanel.cornerRadius
        let insetRect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = borderWidth
        NSColor.systemAccentColor.setStroke()
        path.stroke()
    }
}
