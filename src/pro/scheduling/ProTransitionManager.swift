import Cocoa

/// Separates a user-requested feature from the automatic post-expiration announcement.
enum HardGateReason {
    case feature(ProFeature)
    /// Remembered settings remain available for the final free-pass session.
    case proPreferences(appearanceStyle: AppearanceStylePreference?, shortcut: Bool)
}

/// Contextual copy for blocked feature feedback.
enum ResolvedReason {
    case extraShortcut
    case search
    case appIconsStyle
    case titlesStyle
    case nonEngaged

    var unlockHeader: String {
        switch self {
        case .extraShortcut:
            return NSLocalizedString("Unlock extra shortcuts with Pro", comment: "")
        case .search:
            return NSLocalizedString("Unlock Search with Pro", comment: "")
        case .appIconsStyle:
            return NSLocalizedString("Unlock the App Icons style with Pro", comment: "")
        case .titlesStyle:
            return NSLocalizedString("Unlock the Titles style with Pro", comment: "")
        case .nonEngaged:
            return NSLocalizedString("Get more from AltTab with Pro", comment: "")
        }
    }
}

extension HardGateReason {
    /// Priority order: extraShortcut > search > appIconsStyle / titlesStyle > nonEngaged.
    /// `.proPreferences(_, true)` is search-on-release; the `appearanceStyle` payload distinguishes
    /// `.appIcons` vs `.titles`. `.feature(.autoSize)` falls into `.nonEngaged` (the aspirational
    /// fallback bucket).
    var resolved: ResolvedReason {
        switch self {
        case .feature(.extraShortcut):
            return .extraShortcut
        case .feature(.searchInSwitcher),
             .feature(.searchOnReleaseShortcut):
            return .search
        case .feature(.appIconsAndTitlesStyle):
            // Effectively unreachable: `.appIconsAndTitlesStyle` is degradable, so `attemptUse()`
            // short-circuits before reaching `attemptHardGatedFeature`. Read the live preference
            // as the truthful fallback if it ever does fire.
            switch Preferences.appearanceStyle {
            case .appIcons: return .appIconsStyle
            case .titles: return .titlesStyle
            case .thumbnails: return .nonEngaged
            }
        case let .proPreferences(appearanceStyle, shortcut):
            if shortcut { return .search }
            switch appearanceStyle {
            case .appIcons: return .appIconsStyle
            case .titles: return .titlesStyle
            case .thumbnails, nil: return .nonEngaged
            }
        case .feature(.autoSize):
            return .nonEngaged
        }
    }
}

/// Dispatch after dismissal and focus restoration, away from the switcher's keyboard interaction.
enum PendingDismissAction {
    case showFullUpgrade(HardGateReason?)
    case showDay4Tour
    case showDay35Final
}

/// Presentation requests handled by `ProPromptHost`.
enum ProPromptAction {
    case showWelcome                                      // [A] Day 1
    case showDay4Tour                                     // [H] Day 4
    case showDay15FullUpgrade(HardGateReason?)            // [C] Day 15 full upgrade
    case showDay15HardGatePopover(HardGateReason?)        // [E] post-[C] hard-gate popover
    case showDay35Final                                   // [G] Day 35
    case dismissAllProWindows                             // on upgrade-to-pro
    case refreshBadge                                     // menubar badge dot
}

/// Coordinator for the Pro-transition flow. Wires the license state, the persisted state
/// (`ProTransitionState`), the timed scheduler (`ProTransitionScheduler`), and — via the `onAction`
/// emitter — the Day-X UI. Holds only session-scoped data: the pending dismiss action and a lazy
/// scheduler reference.
class ProTransitionManager {
    static let shared = ProTransitionManager()

    /// Posted after `onProLockEngaged()` or `onProUnlocked()` changes the remembered/stored Pro
    /// selections. Observers (e.g. AppearanceTab, ControlsTab) use this to refresh any UI that
    /// depends on `LicenseManager.isProLocked` while the Settings window is already visible.
    static let proLockStateDidChangeNotification = Notification.Name("ProLockStateDidChange")

    /// Set by the UI layer (see `ProPromptHost`) to receive prompt-action emissions. Decoupled so
    /// the coordinator never references Day-X UI classes directly.
    var onAction: ((ProPromptAction) -> Void)?

    private let makeLicenseManager: () -> LicenseManager
    private lazy var licenseManager = makeLicenseManager()
    let state = ProTransitionState()

    init(licenseManager: @escaping () -> LicenseManager = { LicenseManager.shared }) {
        makeLicenseManager = licenseManager
    }
    private lazy var scheduler: ProTransitionScheduler = .init(
        defaults: ProTransitionState.defaults,
        licenseManager: licenseManager,
        state: state,
        onFire: { [weak self] in self?.evaluateAndShow() }
    )

    private var pendingDismissAction: PendingDismissAction?
    private var deferredPrompt: DispatchWorkItem?
    private var switcherIsShown = false
    var hasPendingPrompt: Bool {
        pendingDismissAction != nil || deferredPrompt != nil || ProPromptHost.windowPresentation.isPending
    }
    #if DEBUG
    var pendingPromptForQa: PendingDismissAction? { pendingDismissAction }
    #endif

    private var freePassPreferencesNeedRefresh = false

    /// Session-scoped: true between the moment a free-pass is granted (either via the
    /// post-expiration switcher trigger in `onSwitcherShown` or via an explicit hard-gate
    /// attempt in `attemptHardGatedFeature`) and the moment the switcher is dismissed.
    /// Read by `PreferenceDefinition.read()` to swap stored free values for the remembered Pro
    /// values so the switcher renders the user's Pro selection one last time. A closing session changes
    /// the reads immediately, but defers AppKit refresh until keyboard release or the next summon.
    private(set) var isFreePassSessionActive: Bool = false {
        didSet {
            guard oldValue != isFreePassSessionActive else { return }
            freePassPreferencesNeedRefresh = true
            if SwitcherSession.current != nil { refreshFreePassPreferencesIfNeeded() }
        }
    }

    func refreshFreePassPreferencesIfNeeded() {
        guard freePassPreferencesNeedRefresh else { return }
        freePassPreferencesNeedRefresh = false
        App.resetPreferencesDependentComponents()
    }

    private func emit(_ action: ProPromptAction) {
        #if DEBUG
        if QaLifecycle.enabled { QaLifecycle.actions.append(String(describing: action)) }
        #endif
        onAction?(action)
    }

    /// Pass-through accessors. The setters are what `QAMenu`'s Reset row writes, so they only look
    /// unused to a scan of the Release scheme, where `QAMenu.swift` is compiled out by its `#if DEBUG`.
    var hasSeenWelcome: Bool { get { state.hasSeenWelcome } set { state.hasSeenWelcome = newValue } }
    // periphery:ignore - written by QAMenu, which the Release scheme compiles out
    var hasSeenDay4Tour: Bool { get { state.hasSeenDay4Tour } set { state.hasSeenDay4Tour = newValue } }
    // periphery:ignore - written by QAMenu, which the Release scheme compiles out
    var freePassUsed: Bool { get { state.freePassUsed } set { state.freePassUsed = newValue } }
    var userOptedOut: Bool {
        get { state.userOptedOut }
        set {
            state.userOptedOut = newValue
            scheduler.scheduleNext()
            guard newValue else { return }
            cancelPendingPrompts()
            SearchDiscoveryHint.shared.cancel()
        }
    }
    // periphery:ignore - written by QAMenu, which the Release scheme compiles out
    var hasTriggeredPostExpirationSwitcher: Bool { get { state.hasTriggeredPostExpirationSwitcher } set { state.hasTriggeredPostExpirationSwitcher = newValue } }

    var shouldShowBadgeDot: Bool {
        ProTransitionManagerTestable.shouldShowBadgeDot(currentState())
    }

    func cancelPendingPrompts() {
        ProPromptHost.windowPresentation.cancel()
        if case .showDay4Tour = pendingDismissAction { state.day4TourDeferred = true }
        deferredPrompt?.cancel()
        deferredPrompt = nil
        pendingDismissAction = nil
    }

    func activeSpaceDidChange() {
        guard ProTransitionManagerTestable.spaceChangeCancelsPendingPrompt(
            switcherIsShown: switcherIsShown, awaitingDismissalDelay: deferredPrompt != nil) else { return }
        cancelPendingPrompts()
    }

    // MARK: - Lifecycle

    private var launchCompleted = false

    func onAppLaunchComplete() {
        launchCompleted = true
        scheduler.onAppLaunchComplete()
    }

    func onLicenseStateChanged() {
        if case .pro = licenseManager.state {
            scheduler.cancel()
            deferredPrompt?.cancel()
            deferredPrompt = nil
            pendingDismissAction = nil
            isFreePassSessionActive = false
            emit(.dismissAllProWindows)
            emit(.refreshBadge)
        }
        // Snapshot + downgrade any degradable Pro selections as soon as the license locks. Idempotent:
        // second entry is a no-op because stored is already the Free equivalent.
        if licenseManager.isProLocked {
            onProLockEngaged()
        }
        if launchCompleted { scheduler.scheduleNext() }
    }

    // MARK: - Hard-gate flow

    /// Called from App.hideUi() when the switcher panel is dismissed.
    func onSwitcherDismissed() {
        switcherIsShown = false
        // End any active free-pass session — the next switcher open should see the free-tier read.
        isFreePassSessionActive = false
        deferredPrompt?.cancel()
        guard pendingDismissAction != nil else { return }
        // Delay so the focused window has time to come to front before our window appears above it.
        let item = DispatchWorkItem { [weak self] in self?.showDeferredPrompt() }
        deferredPrompt = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    func refreshAfterSwitcherDismissal() {
        refreshFreePassPreferencesIfNeeded()
        refreshOutlivedTrialAfterVisibleWork()
    }

    /// The expiry downgrades preferences and rebuilds the switcher's views, so it never runs while the
    /// switcher is open, nor ahead of the dismissal's focus. The next session then starts the free pass.
    private func refreshOutlivedTrialAfterVisibleWork() {
        guard licenseManager.trialEndedSinceLastRefresh else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !switcherIsShown else { return }
            licenseManager.refreshState()
        }
    }

    private func showDeferredPrompt() {
        guard !switcherIsShown, let action = pendingDismissAction else { return }
        pendingDismissAction = nil
        deferredPrompt = nil
        let userInitiated: Bool
        switch action {
        case .showFullUpgrade(.some(.feature)): userInitiated = true
        default: userInitiated = false
        }
        guard userInitiated ? ProPromptHost.sessionIsAvailable : ProPromptHost.canPresentProactively else {
            if case .showDay4Tour = action { state.day4TourDeferred = true }
            return
        }
        if case .pro = licenseManager.state { return }
        switch action {
        case let .showFullUpgrade(feature): showFullUpgradeWindow(for: feature)
        case .showDay4Tour:
            guard ProTransitionManagerTestable.day4TourDays.contains(licenseManager.daysSinceTrialStart), !userOptedOut,
                  Preferences.effectiveAppearanceStyle(0) == .thumbnails else { return }
            emit(.showDay4Tour)
        case .showDay35Final:
            guard ProTransitionManagerTestable.evaluateSwitcherOpen(currentState()) == .showDay35Final else { return }
            emit(.showDay35Final)
        }
    }

    /// Called from App.showUiOrCycleSelection() at the start of a fresh switcher session (not on cycle).
    /// Decides whether to queue a Day 4 tour or a post-expiration free-pass + [C] for after dismissal.
    func onSwitcherShown() {
        guard !switcherIsShown else { return }
        refreshFreePassPreferencesIfNeeded()
        switcherIsShown = true
        ProPromptHost.windowPresentation.cancel()
        ProPromptPopover.cancelPendingPresentations()
        deferredPrompt?.cancel()
        deferredPrompt = nil
        let snapshot = currentState()
        let action = ProTransitionManagerTestable.evaluateSwitcherOpen(snapshot)
        if snapshot.daysSinceTrialStart == 3 && !snapshot.hasSeenDay4Tour {
            state.hasSeenDay4Tour = true
        }
        switch action {
        case .showDay4Tour:
            state.hasSeenDay4Tour = true
            state.day4TourDeferred = true
            pendingDismissAction = .showDay4Tour
        case .triggerFreePass:
            state.freePassUsed = true
            state.hasTriggeredPostExpirationSwitcher = true
            isFreePassSessionActive = true
            let style = state.rememberedAppearanceStyle.flatMap { AppearanceStylePreference.allCases[safe: $0] }
            let reason = HardGateReason.proPreferences(
                appearanceStyle: style,
                shortcut: state.rememberedShortcutStyle != nil)
            if !snapshot.userOptedOut && !snapshot.hasSeenFullUpgrade && !snapshot.hasSeenProactiveDay15 {
                pendingDismissAction = .showFullUpgrade(reason)
            }
        case .showExpiration:
            if pendingDismissAction == nil { pendingDismissAction = .showFullUpgrade(nil) }
        case .showDay35Final:
            pendingDismissAction = .showDay35Final
        case .noop:
            break
        }
    }

    /// Returns true if the feature should be allowed to execute
    func attemptHardGatedFeature(_ feature: ProFeature) -> Bool {
        let action = ProTransitionManagerTestable.evaluateHardGate(currentState())
        if action != .allow && action != .unavailable {
            state.recordIntent(feature.journeyFeature)
        }
        switch action {
        case .unavailable: return false
        case .allow: return true
        case .freePass:
            state.freePassUsed = true
            isFreePassSessionActive = true
            pendingDismissAction = .showFullUpgrade(.feature(feature))
            return true
        case .showFullUpgrade:
            presentBlockedAnnouncement(.feature(feature))
            return false
        case .showHardGatePopover:
            cancelPendingPrompts()
            emit(.showDay15HardGatePopover(.feature(feature)))
            return false
        }
    }

    private func presentBlockedAnnouncement(_ reason: HardGateReason) {
        pendingDismissAction = .showFullUpgrade(reason)
        if SwitcherSession.isActive {
            App.hideUi()
        } else {
            onSwitcherDismissed()
        }
    }

    func showFullUpgradeWindow(for reason: HardGateReason? = nil) {
        pendingDismissAction = nil
        emit(.showDay15FullUpgrade(reason))
    }

    func onProLockEngaged() {
        state.onProLockEngaged()
        NotificationCenter.default.post(name: Self.proLockStateDidChangeNotification, object: nil)
    }

    func onProUnlocked() {
        state.onProUnlocked()
        NotificationCenter.default.post(name: Self.proLockStateDidChangeNotification, object: nil)
    }

    // MARK: - Timed fire dispatch

    private func evaluateAndShow() {
        // Days 13 and 14 have a badge and no prompt, so the icon is redrawn even when nothing may be shown now.
        emit(.refreshBadge)
        guard !switcherIsShown else { return }
        if licenseManager.trialEndedSinceLastRefresh { licenseManager.refreshState() }
        guard !hasPendingPrompt, ProPromptHost.canPresentProactively else { return }
        let action = ProTransitionManagerTestable.evaluateTimedAction(currentState())
        switch action {
        case .showWelcome:
            state.hasSeenWelcome = true
            emit(.showWelcome)
        case .showDay35Final:
            emit(.showDay35Final)
        case .none:
            break
        }
    }

    // MARK: - State snapshot

    func currentState() -> ProTransitionManagerTestable.State {
        state.snapshot(
            licenseState: licenseManager.state,
            daysSinceTrialStart: licenseManager.daysSinceTrialStart,
            clock: licenseManager.clock
        )
    }

    // MARK: - Checkout helper

    static func openCheckout(from origin: CheckoutOrigin) {
        NSWorkspace.shared.open(Endpoints.checkoutUrl(from: origin, trialDay: LicenseManager.shared.trialDay))
    }

    // MARK: - QA / Debug

    #if DEBUG
    func clearSessionForQa() {
        ProPromptHost.windowPresentation.cancel()
        scheduler.cancel()
        scheduler.resetForQa()
        deferredPrompt?.cancel()
        deferredPrompt = nil
        pendingDismissAction = nil
        switcherIsShown = false
        isFreePassSessionActive = false
        state.onboardingInProgress = false
    }

    func resetAllState() {
        clearSessionForQa()
        // Restore any snapshotted Pro selections first so Settings reflects the pre-lock state.
        onProUnlocked()
        state.resetAll()
        NotificationCenter.default.post(name: Self.proLockStateDidChangeNotification, object: nil)
        scheduler.scheduleNext()
    }
    #endif
}

extension HardGateReason {
    /// The automatic announcement has no attempt behind it, so it follows the trial's history instead.
    var attemptedFeature: ProJourneyFeature? {
        guard case let .feature(feature) = self else { return nil }
        return feature.journeyFeature
    }
}

extension ProFeature {
    var journeyFeature: ProJourneyFeature {
        switch self {
        case .searchInSwitcher, .searchOnReleaseShortcut: return .search
        case .appIconsAndTitlesStyle: return .styles
        case .extraShortcut: return .shortcuts
        case .autoSize: return .autoSize
        }
    }
}
