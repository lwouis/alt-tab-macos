import Cocoa

/// Why a hard-gate fired — used by Day 15 Full Upgrade / Hard Gate Popover to render a contextual
/// header. Two sources: a specific `ProFeature` the user attempted, or the aggregated
/// "pro-preferences were configured" signal from the post-expiration first switcher summon.
enum HardGateReason {
    case feature(ProFeature)
    /// Triggered by the first post-expiration switcher summon when the user had a Pro appearance
    /// style or shortcut style configured. The actual `appearanceStyle` (when non-nil, always
    /// `.appIcons` or `.titles`) and the `shortcut` flag let [C] render a tailored header.
    case proPreferences(appearanceStyle: AppearanceStylePreference?, shortcut: Bool)
}

/// Single bucket every `HardGateReason` collapses to via `HardGateReason.resolved`. Lets [C] and
/// [E] render copy from one switch instead of re-implementing precedence rules on the raw enum.
enum ResolvedReason {
    case extraShortcut
    case search
    case appIconsStyle
    case titlesStyle
    case nonEngaged

    /// Header copy shared by [C] Day 15 Full Upgrade and [E] Day 15 Hard Gate Popover.
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
        case .proPreferences(let appearanceStyle, let shortcut):
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

/// Action queued during `showUi` and dispatched 1s after `hideUi` so it appears once the focused
/// window has come back to front. Both Day 4 tour and the post-expiration free-pass share this
/// dismissal-deferred mechanism.
enum PendingDismissAction {
    case showFullUpgrade(HardGateReason?)
    case showDay4Tour
}

/// Side-effect requests emitted by `ProTransitionManager`. A UI-side host (see `ProPromptHost`) owns
/// the concrete window/popover classes and dispatches on this enum. Keeps the coordinator free of
/// direct references to Day-X UI types, so its state-transition logic can be reasoned about without
/// dragging AppKit into the scope.
enum ProPromptAction {
    case showWelcome                                      // [A] Day 1
    case showDay4Tour                                     // [H] Day 4
    case showDay12HeadsUp                                 // [B] Day 12 (also refreshes badge)
    case showDay15Proactive                               // [D] Day 15 proactive
    case showDay15FullUpgrade(HardGateReason?)            // [C] Day 15 full upgrade
    case showDay15HardGatePopover(HardGateReason?)        // [E] post-[C] hard-gate popover
    case showDay21Reminder                                // [F] Day 21
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

    let state = ProTransitionState()
    private lazy var scheduler: ProTransitionScheduler = ProTransitionScheduler(
        defaults: ProTransitionState.defaults,
        licenseManager: LicenseManager.shared,
        state: state,
        onFire: { [weak self] in self?.evaluateAndShow() }
    )

    // session-only: action queued during showUi to fire 1s after dismissal. Used by both the free-pass
    // ladder ([C] Full Upgrade) and the Day 4 mid-trial tour ([H] popover).
    private var pendingDismissAction: PendingDismissAction?

    /// Session-scoped: true between the moment a free-pass is granted (either via the
    /// post-expiration switcher trigger in `onSwitcherShown` or via an explicit hard-gate
    /// attempt in `attemptHardGatedFeature`) and the moment the switcher is dismissed.
    /// Read by `PreferenceDefinition.read()` to swap stored free values for the remembered Pro
    /// values so the switcher renders the user's Pro selection one last time. Each transition
    /// triggers `App.resetPreferencesDependentComponents()` so `TilesView` re-renders against
    /// the new read() result before the panel is shown.
    private(set) var isFreePassSessionActive: Bool = false {
        didSet {
            guard oldValue != isFreePassSessionActive else { return }
            if TilesPanel.shared != nil {
                App.resetPreferencesDependentComponents()
            }
        }
    }

    private func emit(_ action: ProPromptAction) {
        onAction?(action)
    }

    // MARK: - Pass-through accessors for external callers (QAMenu, Day35FinalWindow, etc.)

    var hasSeenWelcome: Bool { get { state.hasSeenWelcome } set { state.hasSeenWelcome = newValue } }
    var hasSeenDay4Tour: Bool { get { state.hasSeenDay4Tour } set { state.hasSeenDay4Tour = newValue } }
    var hasSeenDay12: Bool { get { state.hasSeenDay12 } set { state.hasSeenDay12 = newValue } }
    var freePassUsed: Bool { get { state.freePassUsed } set { state.freePassUsed = newValue } }
    var hasSeenFullUpgrade: Bool { get { state.hasSeenFullUpgrade } set { state.hasSeenFullUpgrade = newValue } }
    var hasSeenProactiveDay15: Bool { get { state.hasSeenProactiveDay15 } set { state.hasSeenProactiveDay15 = newValue } }
    var hasSeenDay21: Bool { get { state.hasSeenDay21 } set { state.hasSeenDay21 = newValue } }
    var hasSeenDay35: Bool { get { state.hasSeenDay35 } set { state.hasSeenDay35 = newValue } }
    var userOptedOut: Bool { get { state.userOptedOut } set { state.userOptedOut = newValue } }
    var hasTriggeredPostExpirationSwitcher: Bool { get { state.hasTriggeredPostExpirationSwitcher } set { state.hasTriggeredPostExpirationSwitcher = newValue } }

    var shouldShowBadgeDot: Bool {
        ProTransitionManagerTestable.shouldShowBadgeDot(currentState())
    }

    // MARK: - Lifecycle

    func onAppLaunchComplete() {
        scheduler.onAppLaunchComplete()
    }

    func onLicenseStateChanged() {
        if case .pro = LicenseManager.shared.state {
            scheduler.cancel()
            emit(.dismissAllProWindows)
            emit(.refreshBadge)
        }
        // Snapshot + downgrade any degradable Pro selections as soon as the license locks. Idempotent:
        // second entry is a no-op because stored is already the Free equivalent.
        if LicenseManager.shared.isProLocked {
            onProLockEngaged()
        }
    }

    // MARK: - Hard-gate flow

    /// Called from App.hideUi() when the switcher panel is dismissed.
    func onSwitcherDismissed() {
        // End any active free-pass session — the next switcher open should see the free-tier read.
        isFreePassSessionActive = false
        guard let action = pendingDismissAction else { return }
        pendingDismissAction = nil
        // delay so the focused window has time to come to front before our window appears above it
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch action {
            case .showFullUpgrade(let feature):
                self.showFullUpgradeWindow(for: feature)
            case .showDay4Tour:
                self.emit(.showDay4Tour)
            }
        }
    }

    /// Called from App.showUiOrCycleSelection() at the start of a fresh switcher session (not on cycle).
    /// Decides whether to queue a Day 4 tour or a post-expiration free-pass + [C] for after dismissal.
    func onSwitcherShown() {
        let action = ProTransitionManagerTestable.evaluateSwitcherOpen(currentState())
        switch action {
        case .showDay4Tour:
            state.hasSeenDay4Tour = true
            pendingDismissAction = .showDay4Tour
        case .triggerFreePass:
            state.freePassUsed = true
            state.hasTriggeredPostExpirationSwitcher = true
            isFreePassSessionActive = true
            let style = state.rememberedAppearanceStyle.flatMap { AppearanceStylePreference.allCases[safe: $0] }
            let reason = HardGateReason.proPreferences(
                appearanceStyle: style,
                shortcut: state.rememberedShortcutStyle != nil)
            pendingDismissAction = .showFullUpgrade(reason)
        case .noop:
            break
        }
    }

    /// Returns true if the feature should be allowed to execute
    func attemptHardGatedFeature(_ feature: ProFeature) -> Bool {
        let action = ProTransitionManagerTestable.evaluateHardGate(currentState())
        switch action {
        case .allow: return true
        case .freePass:
            state.freePassUsed = true
            isFreePassSessionActive = true
            pendingDismissAction = .showFullUpgrade(.feature(feature))
            return true
        case .showFullUpgrade:
            showFullUpgradeWindow(for: .feature(feature))
            return false
        case .showHardGatePopover:
            emit(.showDay15HardGatePopover(.feature(feature)))
            return false
        }
    }

    func showFullUpgradeWindow(for reason: HardGateReason? = nil) {
        // Flip the flag *before* `onProLockEngaged()` so the notification it posts reflects
        // the locked state; otherwise observers re-render with `isProLocked = false` and miss
        // the ghost UI until the next refresh.
        state.hasSeenFullUpgrade = true
        onProLockEngaged()
        emit(.showDay15FullUpgrade(reason))
    }

    func showProactiveDay15Window() {
        state.hasSeenProactiveDay15 = true
        onProLockEngaged()
        emit(.showDay15Proactive)
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
        let action = ProTransitionManagerTestable.evaluateTimedAction(currentState())
        switch action {
        case .showWelcome:
            state.hasSeenWelcome = true
            emit(.showWelcome)
        case .showDay12HeadsUp:
            state.hasSeenDay12 = true
            emit(.showDay12HeadsUp)
        case .showDay15Proactive:
            showProactiveDay15Window()
        case .showDay21Reminder:
            state.hasSeenDay21 = true
            emit(.showDay21Reminder)
        case .showDay35Final:
            state.hasSeenDay35 = true
            emit(.showDay35Final)
        case .refreshBadgeDot:
            emit(.refreshBadge)
        case .none:
            break
        }
    }

    // MARK: - State snapshot

    func currentState() -> ProTransitionManagerTestable.State {
        state.snapshot(
            licenseState: LicenseManager.shared.state,
            daysSinceTrialStart: LicenseManager.shared.daysSinceTrialStart,
            clock: LicenseManager.shared.clock
        )
    }

    // MARK: - Checkout helper

    static func openCheckout() {
        NSWorkspace.shared.open(URL(string: Endpoints.checkoutUrl)!)
    }

    // MARK: - QA / Debug

    #if DEBUG
    func resetAllState() {
        // Restore any snapshotted Pro selections first so Settings reflects the pre-lock state.
        onProUnlocked()
        state.resetAll()
        // onProUnlocked posted while the hasSeen* flags were still set (so `isProLocked` read stale).
        // Now that the flags are cleared, post again so observers re-render with the fresh state.
        NotificationCenter.default.post(name: Self.proLockStateDidChangeNotification, object: nil)
        scheduler.scheduleNext()
    }

    func showComponent(_ show: @autoclosure () -> Void) {
        show()
    }
    #endif
}
