import Cocoa

class TilesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func accessibilityChildren() -> [Any]? {
        let children = super.accessibilityChildren() ?? []
        guard let hint = SearchDiscoveryHint.shared.accessibilityGroup else { return children }
        return children + [hint]
    }
    static var maxPossibleThumbnailSize = NSSize.zero
    static var maxPossibleAppIconSize = NSSize.zero
    static var shared: TilesPanel!
    private var frozenTopCenter: NSPoint?
    private var highWaterHeight: CGFloat = 0

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        applyFloatingPanelChrome()
        TilesView.initialize()
        contentView! = TilesView.contentView
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // for VoiceOver
        setAccessibilityLabel(App.name)
        updateAppearance()
        Self.shared = self
    }

    func updateAppearance() {
        hasShadow = Appearance.enablePanelShadow
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
    }

    func updateContents(_ preservedScrollOrigin: CGPoint?) {
        MainThreadStall.step()
        caTransaction {
            TilesView.updateItemsAndLayout(preservedScrollOrigin)
            guard SwitcherSession.isActive else { return }
            setContentSize(TilesView.contentView.frame.size)
            guard SwitcherSession.isActive else { return }
            repositionOrFreeze()
        }
        // prevent further AppKit work
        TilesView.clearNeedsLayout()
        SearchDiscoveryHint.shared.refreshAfterVisibleWork()
    }


    private func repositionOrFreeze() {
        let size = frame.size
        guard TilesView.isSearchModeOn else {
            NSScreen.preferred.repositionPanel(self)
            resetFrozenPosition()
            return
        }
        if size.height > highWaterHeight {
            NSScreen.preferred.repositionPanel(self)
            highWaterHeight = size.height
            frozenTopCenter = NSPoint(x: frame.midX, y: frame.maxY)
        } else if let topCenter = frozenTopCenter {
            setFrameOrigin(NSPoint(x: topCenter.x - size.width * 0.5, y: topCenter.y - size.height))
        }
    }

    func resetFrozenPosition() {
        frozenTopCenter = nil
        highWaterHeight = 0
    }

    override func orderOut(_ sender: Any?) {
        MainThreadStall.step()
        SearchDiscoveryHint.shared.cancel()
        TilesView.clearNeedsLayout()
        if Preferences.fadeOutAnimation {
            NSAnimationContext.runAnimationGroup(
                { _ in animator().alphaValue = 0 },
                completionHandler: { super.orderOut(sender) }
            )
        } else {
            // Not a hedge against a slow `orderOut`: both land in the same CoreAnimation transaction, which
            // only commits when this runloop turn ends, so nothing here reaches the screen any earlier.
            // It leaves the panel at alpha 0 for the NEXT summon, which is what lets
            // `showUiOrCycleSelection` mask a cross-shortcut rebuild and `show()` reveal it atomically.
            alphaValue = 0
            super.orderOut(sender)
        }
    }

    func show() {
        MainThreadStall.step()
        updateAppearance()
        // The panel may have been hidden (alpha=0) by `App.showUiOrCycleSelection` on a
        // cross-shortcut summon to mask the rebuild. Reveal it atomically now that contents
        // and Appearance are in their final state.
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        // The artificial key-repeat measures its initial-delay grace from when the panel could be SEEN, and this
        // is the only anchor for that which is guaranteed to exist — see `SwitcherSession.panelShownAt`. Set
        // once per summon (a re-show within one session must not restart the grace under the user's fingers).
        if let session = SwitcherSession.current, session.panelShownAt == nil {
            session.panelShownAt = ProcessInfo.processInfo.systemUptime
        }
        ContextMenuEvents.toggle(true)
        CursorEvents.toggle(true)
        DispatchQueue.main.async { TilesView.scrollView.flashScrollers() }
        SearchDiscoveryHint.shared.switcherShown()
    }

    static func maxThumbnailsWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .titles,
           let readableWidth = TilesView.layoutCache.comfortableReadabilityWidth {
            return (
                min(
                    screen.frame.width * Appearance.maxWidthOnScreen,
                    readableWidth + Appearance.intraCellPadding * 2 + Appearance.appIconLabelSpacing + Appearance.iconSize
                    // widthOfLongestTitle + Appearance.intraCellPadding * 2 + Appearance.appIconLabelSpacing + Appearance.iconSize
                ) - Appearance.windowPadding * 2
            ).rounded()
        }
        return (screen.frame.width * Appearance.maxWidthOnScreen - Appearance.windowPadding * 2).rounded()
    }

    static func maxThumbnailsHeight(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return (screen.frame.height * Appearance.maxHeightOnScreen - Appearance.windowPadding * 2).rounded()
    }

    static func updateMaxPossibleThumbnailSize() {
        let (w, h) = NSScreen.screens.reduce((CGFloat.zero, CGFloat.zero)) { acc, screen in
            (max(acc.0, TileView.maxThumbnailWidth(screen) * screen.backingScaleFactor),
            max(acc.1, TileView.maxThumbnailHeight(screen) * screen.backingScaleFactor))
        }
        maxPossibleThumbnailSize = NSSize(width: w.rounded(), height: h.rounded())
    }

    static func updateMaxPossibleAppIconSize() {
        let (w, h) = NSScreen.screens.reduce((CGFloat.zero, CGFloat.zero)) { acc, screen in
            // in Thumbnails Appearance, AppIcons can be used for windowless apps, thus much bigger than the app icon near the title
            if Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .thumbnails {
                return (max(acc.0, TileView.maxThumbnailWidth(screen) * screen.backingScaleFactor),
                    max(acc.1, TileView.maxThumbnailHeight(screen) * screen.backingScaleFactor))
            } else {
                let size = TileView.iconSize(screen)
                return (max(acc.0, size.width * screen.backingScaleFactor),
                    max(acc.1, size.height * screen.backingScaleFactor))
            }
        }
        maxPossibleAppIconSize = NSSize(width: w.rounded(), height: h.rounded())
    }
}

extension TilesPanel: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // other windows can steal key focus from alt-tab; we make sure that if it's active, if keeps key focus
        // dispatching to the main queue is necessary to introduce a delay in scheduling the makeKey; otherwise it is ignored
        DispatchQueue.main.async {
            if SwitcherSession.isActive {
                TilesPanel.shared.makeKeyAndOrderFront(nil)
            }
            MainMenu.toggle(true)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // we toggle the mainMenu off when showing the main window
        // this avoids command+q from quitting AltTab itself, or command+p from printing
        DispatchQueue.main.async {
            MainMenu.toggle(false)
            if TilesView.isSearchEditing {
                MainMenu.toggleEditMenu(true)
            }
        }
        // Refresh the window model once the main run loop next goes idle after showing — i.e. after AppKit has
        // finished ALL the show's main-thread work for this frame. A one-shot kCFRunLoopBeforeWaiting observer
        // fires only when the loop is about to sleep, so it provably can't preempt the render, yet still runs
        // ASAP with no timer guess. (Replaces a 0.25s timer, then a CATransaction-commit hook that fired mid
        // -render and let the reconcile's re-layout race the first frame.)
        let refreshObserver = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { observer, _ in
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            // The show is its own reason to re-read the world, and it does not wait out any quiet period:
            // a correction that lands after the user has already chosen is worth nothing.
            Applications.manuallyRefreshAllWindows()
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), refreshObserver, .commonModes)
    }
}
