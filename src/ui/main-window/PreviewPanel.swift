import Cocoa

class PreviewPanel: NSPanel {
    private let previewView = NSImageView()
    private let borderView = BorderView()
    private var currentId: CGWindowID?

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        contentView = previewView
        borderView.autoresizingMask = [.width, .height]
        previewView.addSubview(borderView)
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
    }

    func show(_ id: CGWindowID, _ preview: NSImage, _ position: CGPoint, _ size: CGSize) {
        if id != currentId  {
            previewView.image = preview
            var frame = NSRect(origin: position, size: size)
            frame.origin.y = NSScreen.preferred().frame.maxY - frame.maxY
            setFrame(frame, display: false)
        }
        if id != currentId || !isVisible {
            alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                animator().alphaValue = 1
            }
            currentId = id
            order(.below, relativeTo: App.app.thumbnailsPanel.windowNumber)
        }
    }
}

private class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 5, yRadius: 5).reversed)
        NSColor.systemAccentColor.withAlphaComponent(0.5).setFill()
        path.fill()
    }
}
