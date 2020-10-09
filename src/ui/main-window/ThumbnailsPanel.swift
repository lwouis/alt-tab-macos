import Cocoa

class ThumbnailsPanel: NSPanel {
    var thumbnailsView = ThumbnailsView()
    override var canBecomeKey: Bool { true }

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
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
