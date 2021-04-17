import Cocoa

class ThumbnailsPanel: NSPanel, NSWindowDelegate {
    var thumbnailsView = ThumbnailsView()
    override var canBecomeKey: Bool { true }

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        updateFadeOutAnimation()
        hidesOnDeactivate = false
        hasShadow = false
        titleVisibility = .hidden
        backgroundColor = .clear
        contentView!.addSubview(thumbnailsView)
        preservesContentDuringLiveResize = false
        disableSnapshotRestoration()
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
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

    func updateFadeOutAnimation() {
        animationBehavior = Preferences.fadeOutAnimation ? .utilityWindow : .none
    }

    func show() {
        makeKeyAndOrderFront(nil)
        MouseEvents.toggle(true)
        thumbnailsView.scrollView.flashScrollers()
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return screen.frame.width * Preferences.maxWidthOnScreen - Preferences.windowPadding * 2
    }

    static func heightMax(_ screen: NSScreen) -> CGFloat {
        return screen.frame.height * Preferences.maxHeightOnScreen - Preferences.windowPadding * 2
    }
}
