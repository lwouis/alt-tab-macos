import Cocoa
import ShortcutRecorder

final class SearchDiscoveryHint {
    static let shared = SearchDiscoveryHint()
    private var history = SearchDiscoveryPolicy.History()
    private var offeredExtra: ExtraShortcutHint?
    private var panel: SearchDiscoveryPanel?
    private var materialKind: EffectViewKind?
    private var material: EffectView?
    private weak var displayedSession: SwitcherSession?
    private var observers = [NSObjectProtocol]()
    private var refreshScheduled = false
    private var initialized = false
    private let defaults = UserDefaults.standard
    #if DEBUG
    private var previewNextSession = false
    private var previewExtraShortcut = false

    func showForQA(extraShortcut: Bool = false) {
        cancel()
        previewNextSession = true
        previewExtraShortcut = extraShortcut
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
        history.hasUsedExtraShortcut = defaults.object(forKey: "searchDiscovery.usedExtra") as? Bool
        history.lastWasExtraShortcut = defaults.bool(forKey: "searchDiscovery.lastWasExtra")
        UsageStats.loadPreviousExtraShortcut { [weak self] used in
            guard let self, history.hasUsedExtraShortcut != true else { return }
            history.hasUsedExtraShortcut = used
        }
        UsageStats.loadPreviousSearch { [weak self] used in
            guard let self else { return }
            history.resolvePreviousSearch(used)
            if history.hasSearched == true {
                persistHistory() }
        }
        observe(NSMenu.didBeginTrackingNotification) { $0.cancel() }
        observe(NSWindow.didBecomeKeyNotification) { hint in
            if hint.isOtherUIBlocking { hint.cancel() }
        }
        observe(NSWindow.didMoveNotification) { $0.refreshAfterVisibleWork() }
        observe(NSWindow.didResizeNotification) { $0.refreshAfterVisibleWork() }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.cancel() }
        observe(ProTransitionManager.proLockStateDidChangeNotification) { $0.refreshAfterVisibleWork() }
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.cancel() }) }
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
        session.searchDiscovery.previewsExtraShortcut = previewExtraShortcut
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
        offeredExtra = extraShortcutCandidate()
        let preferExtra = !history.lastWasExtraShortcut && offeredExtra != nil && history.hasUsedExtraShortcut == false
        if !preferExtra, history.hasSearched == false, usableShortcut() != nil,
           Windows.list.count(where: { $0.shouldShowTheUser && !$0.isWindowlessApp }) >= SearchDiscoveryPolicy.minimumWindows {
            offeredExtra = nil
        }
        #if DEBUG
        if session.searchDiscovery.isPreview {
            offeredExtra = session.searchDiscovery.previewsExtraShortcut ? extraShortcutCandidate() : nil
        }
        #endif
        let now = LicenseManager.shared.clock.now
        guard session.searchDiscovery.isReady(current: SwitcherSession.current?.searchDiscovery,
                                              now: ProcessInfo.processInfo.systemUptime),
              let shortcut = offeredExtra?.shortcut ?? usableShortcut(), session.searchDiscovery.isEligible(context: context(), history: history),
              !session.searchDiscovery.recordsHistory || history.canPresent(at: now),
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
        history.lastWasExtraShortcut = offeredExtra != nil
        history.recordExposure(at: now)
        ProTransitionManager.shared.state.recordMessage()
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

    func extraShortcutWasUsed() {
        guard history.hasUsedExtraShortcut != true else { return }
        history.hasUsedExtraShortcut = true
        cancel()
        DispatchQueue.main.async { self.persistHistory()
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
            offeredExtra == nil || extraShortcutCandidate() != nil,
            let shortcut = offeredExtra?.shortcut ?? usableShortcut(), let panel, let frame = prepareFrame(panel, shortcut) else {
            cancel()
            return
        }
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    private func prepareFrame(_ panel: SearchDiscoveryPanel, _ shortcut: Shortcut) -> NSRect? {
        guard let screen = TilesPanel.shared.screen, let label = SearchDiscoveryShortcut.label(shortcut) else { return nil }
        let kind = requiredEffectViewKind()
        if materialKind != kind {
            material = makeEffectView(for: kind)
            materialKind = kind
            panel.setMaterial(material!)
        }
        material?.updateAppearance(cornerRadius: 0)
        let size = panel.prepare(shortcut: label,
                                 spokenShortcut: shortcut.readableStringRepresentation(isASCII: false),
                                 dark: Appearance.currentTheme == .dark,
                                 highContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                                 maxWidth: screen.visibleFrame.width - 16,
                                 title: offeredExtra?.title, instruction: offeredExtra?.instruction,
                                 holdKey: offeredExtra.map { (label: $0.holdLabel, spoken: $0.holdSpoken) })
        return SearchDiscoveryPolicy.frame(size: size, switcher: TilesPanel.shared.frame, visibleScreen: screen.visibleFrame)
    }

    private func context() -> SearchDiscoveryPolicy.Context {
        let license = LicenseManager.shared
        let access: SearchDiscoveryPolicy.Access
        switch license.state {
        case .trial: access = .trial(day: license.daysSinceTrialStart)
        case .pro: access = .pro
        case .trialNotStarted, .trialExpired, .proExpired: access = .locked
        }
        return SearchDiscoveryPolicy.Context(access: access,
            windowCount: Windows.list.count { $0.shouldShowTheUser && !$0.isWindowlessApp },
            enabled: CachedUserDefaults.bool("showSearchHint"), optedOut: ProTransitionManager.shared.userOptedOut,
            searchActive: TilesView.isSearchModeOn,
            blockedByOtherUI: isOtherUIBlocking || ProTransitionManager.shared.hasPendingPrompt,
            hasShortcut: offeredExtra != nil || usableShortcut() != nil,
                                             extraShortcut: offeredExtra != nil)
    }

    private var isOtherUIBlocking: Bool {
        ScreenLockEvents.isScreenLocked || ProTransitionManager.shared.state.onboardingInProgress ||
            ContextMenuEvents.isMenuOpen || ProPromptPopover.isShowing || NSApp.modalWindow != nil
            || NSApp.windows.contains { $0.isVisible && ($0 is ProPromptWindow || $0 is PermissionsWindow || $0 is SettingsWindow ||
                        $0 is FeedbackWindow) }
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

    private struct ExtraShortcutHint {
        let shortcut: Shortcut
        let title: String
        let instruction: String
        let holdLabel: String
        let holdSpoken: String
    }

    private func extraShortcutCandidate() -> ExtraShortcutHint? {
        guard SwitcherSession.activeShortcutIndex == 0, Preferences.appsToShow[0] == .all,
              let pid = Applications.frontmostPid,
              let app = Applications.list.first(where: { $0.pid == pid }), let name = app.localizedName,
              let hold = ControlsTab.shortcuts["holdShortcut"]?.shortcut,
              !hold.modifierFlags.isEmpty,
              let holdLabel = SearchDiscoveryShortcut.label(hold) else { return nil }
        let windows = Windows.list.filter { $0.shouldShowTheUser && !$0.isWindowlessApp }
        guard SearchDiscoveryPolicy.canDemonstrateActiveApp(
            activeWindows: windows.count(where: { $0.application.pid == pid }),
            totalWindows: windows.count) else { return nil }
        let matchingFilters = [
            "spacesToShow",
            "screensToShow",
            "showMinimizedWindows",
            "showHiddenWindows",
            "showFullscreenWindows",
            "showAppsOrWindows",
            "showTabsAsWindows",
        ]
        for index in 1 ..< Preferences.shortcutCount {
            guard Preferences.appsToShow[index] == .active, Preferences.groupApps(index) == .allWindows,
                  matchingFilters.allSatisfy({
                      UserDefaults.standard.string(forKey: $0) == UserDefaults.standard.string(
                          forKey: Preferences.indexToName(
                              $0,
                              index
                          )
                      ) }),
                  let targetHold = ControlsTab.shortcuts[Preferences.indexToName(
                      "holdShortcut",
                      index
                  )]?.shortcut,
                  targetHold.carbonModifierFlags.cleaned() == hold.carbonModifierFlags.cleaned(),
                  let next = ControlsTab.shortcuts[Preferences.indexToName(
                      "nextWindowShortcut",
                      index
                  )]?.shortcut,
                  next.keyCode != .none,
                  next.carbonModifierFlags.cleaned() == hold.carbonModifierFlags.cleaned(),
                  let _ = SearchDiscoveryShortcut.label(Shortcut(
                      code: next.keyCode,
                      modifierFlags: [],
                      characters: nil,
                      charactersIgnoringModifiers: nil
                  )) else { continue }
            let conflicts = ControlsTab.shortcuts.contains { id, entry in
                id != Preferences.indexToName("nextWindowShortcut", index) && !id.hasPrefix("holdShortcut")
                    && (entry.scope == .local || id.hasPrefix("nextWindowShortcut"))
                    && entry.shortcut.keyCode == next.keyCode
                    &&
                    (entry.shortcut.carbonModifierFlags.cleaned() |
                        hold.carbonModifierFlags.cleaned()) == next.carbonModifierFlags.cleaned()
            }
            guard !conflicts else { continue }
            let title = String(
                format: NSLocalizedString("Show only %@ windows (active app)", comment: ""),
                name
            )
            return ExtraShortcutHint(
                shortcut: Shortcut(code: next.keyCode, modifierFlags: [], characters: nil,
                                   charactersIgnoringModifiers: nil),
                title: title,
                instruction: NSLocalizedString("Keep holding %@ then press %@", comment: ""),
                holdLabel: holdLabel,
                holdSpoken: hold.readableStringRepresentation(isASCII: false)
            )
        }
        return nil
    }

    private func persistHistory() {
        if let used = history.hasUsedExtraShortcut {
            defaults.set(used, forKey: "searchDiscovery.usedExtra")
        }
        defaults.set(history.lastWasExtraShortcut, forKey: "searchDiscovery.lastWasExtra")
        defaults.set(history.hasSearched == true, forKey: "searchDiscovery.hasSearched")
        defaults.set(history.exposures, forKey: "searchDiscovery.exposures")
        defaults.set(history.lastExposure, forKey: "searchDiscovery.lastExposure")
    }
}
