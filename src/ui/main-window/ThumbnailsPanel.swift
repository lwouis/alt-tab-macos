import Cocoa

class ThumbnailsPanel: NSPanel, NSWindowDelegate {
    var thumbnailsView = ThumbnailsView()
    override var canBecomeKey: Bool { true }

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        hasShadow = Appearance.enablePanelShadow
        titleVisibility = .hidden
        backgroundColor = .clear
        contentView! = thumbnailsView
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
        // for VoiceOver
        setAccessibilityLabel(App.name)
    }

    func windowDidResignKey(_ notification: Notification) {
        // other windows can steal key focus from alt-tab; we make sure that if it's active, if keeps key focus
        // dispatching to the main queue is necessary to introduce a delay in scheduling the makeKey; otherwise it is ignored
        DispatchQueue.main.async {
            if App.app.appIsBeingUsed {
                App.app.thumbnailsPanel.makeKeyAndOrderFront(nil)
            }
        }
    }

    override func orderOut(_ sender: Any?) {
        if Preferences.fadeOutAnimation {
            NSAnimationContext.runAnimationGroup(
                { _ in animator().alphaValue = 0 },
                completionHandler: { super.orderOut(sender) }
            )
        } else {
            super.orderOut(sender)
        }
    }

    func show() {
        hasShadow = Appearance.enablePanelShadow
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        MouseEvents.toggle(true)
        thumbnailsView.scrollView.flashScrollers()
    }

    /// The maximum height that thumbnails can be drawn.
    /// - Parameter screen:
    /// - Returns:
    static func maxThumbnailsWidth(_ screen: NSScreen) -> CGFloat {
        return screen.frame.width * Appearance.maxWidthOnScreen - Appearance.windowPadding * 2
    }

    /// The maximum height that thumbnails can be drawn.
    ///
    /// - Parameter screen:
    /// - Returns:
    static func maxThumbnailsHeight(_ screen: NSScreen) -> CGFloat {
        return screen.frame.height * Appearance.maxHeightOnScreen - Appearance.windowPadding * 2
    }
}
