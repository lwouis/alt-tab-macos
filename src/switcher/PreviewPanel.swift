import Cocoa

class PreviewPanel: NSPanel {
    private static let previewView = LightImageView()
    private static let borderView = BorderView()
    private static var currentId: CGWindowID?
    static var shared: PreviewPanel!
    private(set) static var windowId: CGWindowID?

    /// `.titled` would make it eligible, and the preview outlives the switcher after a focus (`beginHideUi`'s
    /// `keepPreview`): ordering out the key `TilesPanel` once the target is front made AppKit hand key to this
    /// panel, so AltTab took the keyboard back from the window just focused (#6113, QA S-21).
    override var canBecomeKey: Bool { false }

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
        Self.windowId = CGWindowID(windowNumber)
    }

    /// `area` is top-left global: what the preview's capture covers, which a sheet can make larger than the window
    static func show(_ id: CGWindowID, _ preview: CALayerContents, _ area: CGRect) {
        repositionAndResize(area)
        if id != currentId {
            previewView.updateContents(preview, area.size)
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

    static func updateIfShowing(_ id: CGWindowID?, _ preview: CALayerContents, _ area: CGRect) {
        if Self.shared.isVisible && id == currentId {
            repositionAndResize(area)
            previewView.updateContents(preview, area.size)
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

    private static func repositionAndResize(_ area: CGRect) {
        var frame = area
        // Flip Y coordinate from Quartz (0,0 at bottom-left) to Cocoa coordinates (0,0 at top-left)
        // Always use the primary screen as reference since all coordinates are relative to it
        frame.origin.y = NSScreen.screens.first!.frame.maxY - frame.maxY
        Self.shared.setFrame(frame, display: false)
        SearchDiscoveryHint.shared.refreshAfterVisibleWork()
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
