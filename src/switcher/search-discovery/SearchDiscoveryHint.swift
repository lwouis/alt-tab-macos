import Cocoa
import ShortcutRecorder

final class SearchDiscoveryHint {
    static let shared = SearchDiscoveryHint()
    private var history = SearchDiscoveryPolicy.History()
    private var panel: SearchDiscoveryPanel?
    private var backgroundKind: EffectViewKind?
    private weak var displayedSession: SwitcherSession?
    private var observers = [NSObjectProtocol]()
    private var refreshScheduled = false
    private var initialized = false
    private let defaults = UserDefaults.standard
    #if DEBUG
    private var previewNextSession = false

    func showForQA() {
        cancel()
        previewNextSession = true
    }
    #endif

    var containsMouseLocation: Bool {
        guard displayedSession != nil, let panel, panel.isVisible, panel.alphaValue > 0 else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    var accessibilityGroup: NSView? {
        displayedSession == nil ? nil : panel?.contentView
    }

    func initialize() {
        guard !initialized else { return }
        initialized = true
        history = SearchDiscoveryPolicy.History(
            hasSearched: history.hasSearched == true || defaults.bool(forKey: "searchDiscovery.hasSearched") ? true : nil,
            exposures: defaults.integer(forKey: "searchDiscovery.exposures"),
            lastExposure: defaults.object(forKey: "searchDiscovery.lastExposure") as? Date)
        UsageStats.loadPreviousSearch { [weak self] used in
            guard let self else { return }
            self.history.resolvePreviousSearch(used)
            if self.history.hasSearched == true { self.persistHistory() }
        }
        observe(NSMenu.didBeginTrackingNotification) { $0.cancel() }
        observe(NSWindow.didBecomeKeyNotification) { hint in
            if hint.isOtherUIBlocking { hint.cancel() }
        }
        observe(NSWindow.didMoveNotification) { $0.refreshAfterVisibleWork() }
        observe(NSWindow.didResizeNotification) { $0.refreshAfterVisibleWork() }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.cancel() }
        observe(ProTransitionManager.proLockStateDidChangeNotification) { $0.refreshAfterVisibleWork() }
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAfterVisibleWork() }
        observers.append(observer)
    }

    private func observe(_ name: Notification.Name, _ action: @escaping (SearchDiscoveryHint) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            if let self { action(self) }
        })
    }

    func switcherShown() {
        guard initialized, let session = SwitcherSession.current, session.searchDiscovery.schedule() else { return }
        #if DEBUG
        session.searchDiscovery.isPreview = previewNextSession
        previewNextSession = false
        #endif
        // Start on the next turn, after the transaction revealing the switcher can commit.
        DispatchQueue.main.async { [weak session] in
            guard let session, session === SwitcherSession.current else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + SearchDiscoveryPolicy.displayDelay) { [weak session] in
                guard let session else { return }
                self.presentIfEligible(session)
            }
        }
    }

    private func presentIfEligible(_ session: SwitcherSession) {
        MainThreadStall.step()
        guard session.searchDiscovery.isReady(current: SwitcherSession.current?.searchDiscovery,
                                              now: ProcessInfo.processInfo.systemUptime),
              let shortcut = usableShortcut(), session.searchDiscovery.isEligible(context: context(), history: history),
              !session.searchDiscovery.recordsHistory || history.canPresent(at: Date()),
              TilesPanel.shared.isVisible, TilesPanel.shared.alphaValue > 0 else { return }
        let hint = panel ?? SearchDiscoveryPanel()
        panel = hint
        let recordsHistory = session.searchDiscovery.recordsHistory
        hint.onDismiss = { [weak self] in
            self?.cancel()
            if recordsHistory { Preferences.set("showSearchHint", false) }
        }
        guard let frame = prepareFrame(hint, shortcut) else { return }
        hint.setFrame(frame, display: false)
        guard session.searchDiscovery.isReady(current: SwitcherSession.current?.searchDiscovery,
                                              now: ProcessInfo.processInfo.systemUptime),
              session.searchDiscovery.isEligible(context: context(), history: history) else { return }
        displayedSession = session
        hint.contentView?.setAccessibilityParent(TilesPanel.shared)
        hint.level = TilesPanel.shared.level
        hint.alphaValue = 1
        TilesPanel.shared.addChildWindow(hint, ordered: .above)
        guard recordsHistory else { return }
        history.recordExposure(at: Date())
        persistHistory()
    }

    func cancel() {
        SwitcherSession.current?.searchDiscovery.cancel()
        displayedSession?.searchDiscovery.cancel()
        displayedSession = nil
        guard let panel, panel.alphaValue > 0 else { return }
        panel.alphaValue = 0
        // Do not order another AppKit window out before the switcher's dismissal/focus has rendered.
        DispatchQueue.main.async { [weak self, weak panel] in
            guard self?.displayedSession == nil, let panel, panel.alphaValue == 0 else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    func searchWasUsed() {
        history.recordSearch()
        cancel()
        DispatchQueue.main.async { self.persistHistory() }
    }

    func refreshAfterVisibleWork() {
        guard displayedSession != nil, !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async {
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        guard let session = displayedSession else { return }
        guard session === SwitcherSession.current, session.searchDiscovery.isEligible(context: context(), history: history),
              let shortcut = usableShortcut(), let panel, let frame = prepareFrame(panel, shortcut) else {
            cancel()
            return
        }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    private func prepareFrame(_ panel: SearchDiscoveryPanel, _ shortcut: Shortcut) -> NSRect? {
        guard let screen = TilesPanel.shared.screen, let label = SearchDiscoveryShortcut.label(shortcut) else { return nil }
        let background = matchSwitcherBackground(panel)
        let size = panel.prepare(shortcut: label,
                                 spokenShortcut: shortcut.readableStringRepresentation(isASCII: false),
                                 dark: Appearance.currentTheme == .dark,
                                 highContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                                 maxWidth: screen.visibleFrame.width - 16,
                                 maxCornerRadius: Appearance.windowCornerRadius)
        background.updateAppearance(cornerRadius: panel.cornerRadius)
        panel.hasShadow = Appearance.enablePanelShadow
        let preview = PreviewPanel.shared
        return SearchDiscoveryPolicy.frame(size: size, switcher: TilesPanel.shared.frame,
                                           visibleScreen: screen.visibleFrame,
                                           obstruction: preview?.isVisible == true ? preview?.frame : nil)
    }

    /// The switcher's own kind of background, so the hint reads as part of it. Rebuilt when that kind
    /// changes (e.g. the App Icons style uses clear glass).
    private func matchSwitcherBackground(_ panel: SearchDiscoveryPanel) -> EffectView {
        let kind = TilesView.currentEffectViewKind ?? requiredEffectViewKind()
        if kind == backgroundKind, let current = panel.background as? EffectView { return current }
        let view = makeEffectView(for: kind)
        panel.setBackground(view, host: view.hostView)
        backgroundKind = kind
        return view
    }

    private func context() -> SearchDiscoveryPolicy.Context {
        let license = LicenseManager.shared
        let access: SearchDiscoveryPolicy.Access
        switch license.state {
        case .trial: access = .trial(day: license.daysSinceTrialStart)
        case .pro: access = .pro
        case .trialExpired, .proExpired: access = .locked
        }
        return SearchDiscoveryPolicy.Context(access: access,
            windowCount: Windows.list.count { $0.shouldShowTheUser && !$0.isWindowlessApp },
            enabled: CachedUserDefaults.bool("showSearchHint"), optedOut: ProTransitionManager.shared.userOptedOut,
            searchActive: TilesView.isSearchModeOn,
            blockedByOtherUI: isOtherUIBlocking || ProTransitionManager.shared.hasPendingPrompt,
            hasShortcut: usableShortcut() != nil)
    }

    private var isOtherUIBlocking: Bool {
        ContextMenuEvents.isMenuOpen || ProPromptPopover.isShowing || NSApp.modalWindow != nil
            || NSApp.windows.contains { $0.isVisible && ($0 is ProPromptWindow || $0 is PermissionsWindow) }
    }

    private func usableShortcut() -> Shortcut? {
        guard let shortcut = ControlsTab.shortcuts["searchShortcut"]?.shortcut,
              shortcut.keyCode != .none || !shortcut.modifierFlags.isEmpty else { return nil }
        let index = SwitcherSession.activeShortcutIndex
        let hold = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", index)]?.shortcut.carbonModifierFlags.cleaned() ?? 0
        let modifiers = shortcut.carbonModifierFlags.cleaned() | hold
        let next = Preferences.indexToName("nextWindowShortcut", index)
        guard !ControlsTab.shortcuts.contains(where: { key, entry in
            guard key != "searchShortcut", entry.scope == .local || key == next,
                  entry.index == nil || entry.index == index else { return false }
            let other = entry.shortcut
            return other.keyCode == shortcut.keyCode && (other.carbonModifierFlags.cleaned() | hold) == modifiers
        }) else { return nil }
        return shortcut
    }

    private func persistHistory() {
        defaults.set(history.hasSearched == true, forKey: "searchDiscovery.hasSearched")
        defaults.set(history.exposures, forKey: "searchDiscovery.exposures")
        defaults.set(history.lastExposure, forKey: "searchDiscovery.lastExposure")
    }
}
