import Cocoa

class PreviewPanel: NSPanel {
    private static let previewView = LightImageView()
    private static let borderView = BorderView()
    private static var currentId: CGWindowID?
    static var shared: PreviewPanel!

    /// this allows the window to be above the menubar when its origin.y is set to 0
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        applyFloatingPanelChrome()
        titlebarAppearsTransparent = true
        contentView = Self.previewView
        Self.borderView.autoresizingMask = [.width, .height]
        Self.previewView.addSubview(Self.borderView)
        Self.shared = self
    }

    static func show(_ id: CGWindowID, _ preview: CALayerContents, _ position: CGPoint, _ size: CGSize) {
        repositionAndResize(position, size)
        if id != currentId {
            previewView.updateContents(preview, size)
        }
        if id != currentId || !Self.shared.isVisible {
            if Preferences.previewFadeInAnimation {
                Self.shared.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    Self.shared.animator().alphaValue = 1
                }
            }
            currentId = id
            Self.shared.order(.below, relativeTo: TilesPanel.shared.windowNumber)
            // Despite using `previewPanel.order(.below)`, a z-ordering issue can occur in the following scenario:
            // 1. Show a preview of a window that is on a different monitor than the thumbnails panel
            // 2. Select a window in the switcher that is on the same monitor as the thumbnails panel, and whose position overlaps with the thumbnails panel
            // 3. For a single frame, the preview of the newly selected window can appear above the thumbnails panel before going back underneath it
            // Simply using order(.below) is not sufficient to prevent this brief flicker. We explicitly set the preview panel's window level to be one below the thumbnails panel
            Self.shared.level = NSWindow.Level(rawValue: TilesPanel.shared.level.rawValue - 1)
        }
    }

    static func updateIfShowing(_ id: CGWindowID?,  _ preview: CALayerContents, _ position: CGPoint, _ size: CGSize) {
        if Self.shared.isVisible && id == currentId {
            repositionAndResize(position, size)
            previewView.updateContents(preview, size)
        }
    }

    /// Order out AND release the displayed frame: the layer would otherwise pin a full-resolution
    /// frame in this static view for the rest of the app's lifetime, defeating the session-scoped
    /// Preview-frame cache's release-on-hide (#5861).
    static func hide() {
        Self.shared.orderOut(nil)
        previewView.releaseImage()
        currentId = nil
    }

    /// Called when a window is removed from `Windows.list`: if our preview was showing that
    /// window, drop the cached IOSurface in `previewView.contents` so it can deallocate.
    /// Without this, closing the previewed window in the background leaves its full-resolution
    /// screenshot pinned in the static `previewView` for the rest of the app's lifetime.
    static func clearIfShowing(_ wid: CGWindowID) {
        if currentId == wid {
            previewView.releaseImage()
            currentId = nil
        }
    }

    private static func repositionAndResize( _ position: CGPoint, _ size: CGSize) {
        var frame = NSRect(origin: position, size: size)
        // Flip Y coordinate from Quartz (0,0 at bottom-left) to Cocoa coordinates (0,0 at top-left)
        // Always use the primary screen as reference since all coordinates are relative to it
        frame.origin.y = NSScreen.screens.first!.frame.maxY - frame.maxY
        Self.shared.setFrame(frame, display: false)
    }
}

private class BorderView: NSView {
    @available(macOS 27.0, *)
    override var cornerConfiguration: NSViewCornerConfiguration? {
        .uniformCorners(radius: .containerConcentric)
    }

    @available(macOS 27.0, *)
    override func viewDidChangeEffectiveCornerRadii() {
        super.viewDidChangeEffectiveCornerRadii()
        updateNativeBorder()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if #available(macOS 27.0, *) { updateNativeBorder() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if #available(macOS 27.0, *) { updateNativeBorder() }
    }

    @available(macOS 27.0, *)
    private func updateNativeBorder() {
        wantsLayer = true
        layer!.cornerRadius = effectiveCornerRadii?.topLeft ?? 0
        layer!.cornerCurve = .continuous
        layer!.borderWidth = 5
        layer!.borderColor = NSColor.systemAccentColor.withAlphaComponent(0.5).cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        if #available(macOS 27.0, *) { return }
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 5, yRadius: 5).reversed)
        NSColor.systemAccentColor.withAlphaComponent(0.5).setFill()
        path.fill()
    }
}
