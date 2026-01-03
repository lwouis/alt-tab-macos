import Cocoa

class PreviewPanel: NSPanel {
    private let previewView = LightImageView()
    private let borderView = BorderView()
    private var currentId: CGWindowID?

    /// this allows the window to be above the menubar when its origin.y is set to 0
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
        contentView = previewView
        borderView.autoresizingMask = [.width, .height]
        previewView.addSubview(borderView)
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
    }

    func show(_ id: CGWindowID, _ image: CGImage, _ position: CGPoint, _ size: CGSize) {
        if id != currentId {
            repositionAndResize(position, size)
            previewView.updateWithResizedCopy(image, size)
        }
        if id != currentId || !isVisible {
            if Preferences.previewFadeInAnimation {
                alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    animator().alphaValue = 1
                }
            }
            currentId = id
            order(.below, relativeTo: App.app.thumbnailsPanel.windowNumber)
            // Despite using `previewPanel.order(.below)`, a z-ordering issue can occur in the following scenario:
            // 1. Show a preview of a window that is on a different monitor than the thumbnails panel
            // 2. Select a window in the switcher that is on the same monitor as the thumbnails panel, and whose position overlaps with the thumbnails panel
            // 3. For a single frame, the preview of the newly selected window can appear above the thumbnails panel before going back underneath it
            // Simply using order(.below) is not sufficient to prevent this brief flicker. We explicitly set the preview panel's window level to be one below the thumbnails panel
            level = NSWindow.Level(rawValue: App.app.thumbnailsPanel.level.rawValue - 1)
        }
    }

    func updateIfShowing(_ id: CGWindowID?,  _ image: CGImage, _ position: CGPoint, _ size: CGSize) {
        if isVisible && id == currentId {
            repositionAndResize(position, size)
            previewView.updateWithResizedCopy(image, size)
        }
    }

    private func repositionAndResize( _ position: CGPoint, _ size: CGSize) {
        var frame = NSRect(origin: position, size: size)
        // Flip Y coordinate from Quartz (0,0 at bottom-left) to Cocoa coordinates (0,0 at top-left)
        // Always use the primary screen as reference since all coordinates are relative to it
        frame.origin.y = NSScreen.screens.first!.frame.maxY - frame.maxY
        setFrame(frame, display: false)
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
