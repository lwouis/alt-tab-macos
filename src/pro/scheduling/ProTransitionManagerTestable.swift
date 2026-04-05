/// Pure decision logic for the Pro transition state machine.
/// No singletons, no Date(), no UI, no side effects — just inputs → outputs.
/// This makes the complex state machine fully unit-testable.
struct ProTransitionManagerTestable {

    // MARK: - State snapshot (all inputs the decisions depend on)

    struct State {
        var isPro: Bool
        var isTrialActive: Bool // true for .trial, false for .trialExpired
        var daysSinceTrialStart: Int // 0-indexed: Day 1 = 0, Day 12 = 11, Day 15 = 14
        var isInTimeWindow: Bool
        var hasSeenWelcome: Bool
        var hasSeenDay4Tour: Bool
        var hasSeenDay12: Bool
        var freePassUsed: Bool
        var hasSeenFullUpgrade: Bool
        var hasSeenProactiveDay15: Bool
        var hasSeenDay21: Bool
        var hasSeenDay35: Bool
        var userOptedOut: Bool
        var hasTriggeredPostExpirationSwitcher: Bool

        static func fresh() -> State {
            State(isPro: false, isTrialActive: true, daysSinceTrialStart: 0, isInTimeWindow: false,
                  hasSeenWelcome: false, hasSeenDay4Tour: false, hasSeenDay12: false, freePassUsed: false,
                  hasSeenFullUpgrade: false, hasSeenProactiveDay15: false,
                  hasSeenDay21: false, hasSeenDay35: false,
                  userOptedOut: false,
                  hasTriggeredPostExpirationSwitcher: false)
        }
    }

    // MARK: - Action enums (outputs)

    enum TimedAction: Equatable {
        case showWelcome          // [A]
        case showDay12HeadsUp     // [B]
        case showDay15Proactive   // [D]
        case showDay21Reminder    // [F]
        case showDay35Final       // [G]
        case refreshBadgeDot
        case none
    }

    enum HardGateAction: Equatable {
        case allow                // pro or trial active
        case freePass             // first hard-gate after expiry — allow once, then show [C]
        case showFullUpgrade      // [C]
        case showHardGatePopover  // [E] — shown on every post-[C] hard-gate attempt
    }

    /// What should happen when the switcher is opened (a fresh summon, not a cycle)?
    enum SwitcherOpenAction: Equatable {
        case showDay4Tour          // [H] — fires once on Day 4
        case triggerFreePass       // post-expiration first summon when a Pro style or shortcut was configured
        case noop
    }

    // MARK: - Pure decision functions

    /// What should happen on a timed evaluation (scheduler fire or app launch)?
    static func evaluateTimedAction(_ s: State) -> TimedAction {
        if s.isPro { return .none }

        // Day 1: Welcome letter
        if !s.hasSeenWelcome {
            return .showWelcome
        }

        // Day 12 only (daysSinceTrialStart == 11): Heads-up popover. Spec: "If missed, try 15:30–17:00, then skip entirely" — do not retry on Day 13+.
        if s.daysSinceTrialStart == 11 && !s.hasSeenDay12 && s.isInTimeWindow {
            return .showDay12HeadsUp
        }

        // Day 15+ (daysSinceTrialStart >= 14): Proactive window (only if no hard-gate fired yet)
        if s.daysSinceTrialStart >= 14 && !s.hasSeenProactiveDay15 && !s.hasSeenFullUpgrade && s.isInTimeWindow {
            return .showDay15Proactive
        }

        // Day 35+ (daysSinceTrialStart >= 34): Final window (give up at Day 49 / daysSinceTrialStart 48).
        // Checked before Day 21 so a user inactive through Day 35 sees [G] instead of [F] (spec: "If Day 35 arrives first, skip Day 21").
        if s.daysSinceTrialStart >= 34 && s.daysSinceTrialStart < 48 && !s.hasSeenDay35 && s.isInTimeWindow {
            return .showDay35Final
        }

        // Day 21–34 (daysSinceTrialStart 20..<34): Reminder popover. Upper bound prevents [F] firing on/after Day 35 or past Day 49.
        if s.daysSinceTrialStart >= 20 && s.daysSinceTrialStart < 34 && !s.hasSeenDay21 && s.isInTimeWindow {
            return .showDay21Reminder
        }

        // Day 15+: refresh badge dot (removal) even if no prompt shown
        if s.daysSinceTrialStart >= 14 {
            return .refreshBadgeDot
        }

        return .none
    }

    /// What should happen when a hard-gated feature is attempted?
    static func evaluateHardGate(_ s: State) -> HardGateAction {
        if s.isPro || s.isTrialActive { return .allow }
        if !s.freePassUsed { return .freePass }
        if !s.hasSeenFullUpgrade { return .showFullUpgrade }
        return .showHardGatePopover
    }

    /// What should happen on a fresh switcher open (not a cycle of an existing session)?
    /// Two distinct triggers, both deferred until `hideUi()` so the popover/window appears after dismissal:
    /// 1. Day 4 mid-trial Pro tour — once-ever, only on Day 4 exactly.
    /// 2. Post-expiration switcher trigger — once-ever, fires for every user (engaged or not). The
    ///    `HardGateReason` carries the remembered Pro selections when present so [C] can render a
    ///    tailored header; otherwise it resolves to `.nonEngaged`.
    static func evaluateSwitcherOpen(_ s: State) -> SwitcherOpenAction {
        if s.isPro { return .noop }
        if s.isTrialActive {
            if s.daysSinceTrialStart == 3 && !s.hasSeenDay4Tour { return .showDay4Tour }
            return .noop
        }
        // Trial expired: trigger free-pass + [C] on first summon, regardless of which Pro features were
        // configured. For users with no remembered* values, the reason resolves to `.nonEngaged` and the
        // free-pass session is a harmless no-op (read() falls back to stored Free defaults).
        if !s.hasTriggeredPostExpirationSwitcher && !s.freePassUsed {
            return .triggerFreePass
        }
        return .noop
    }

    /// Should the menubar icon show a badge dot?
    /// Pro users never see the badge — spec: "Purchase at any point → all indicators cleared."
    static func shouldShowBadgeDot(_ s: State) -> Bool {
        !s.isPro && s.isTrialActive && s.daysSinceTrialStart >= 12 && s.daysSinceTrialStart <= 13
    }

    /// Is scheduling done (no more timed events to fire)?
    static func isSchedulingComplete(_ s: State) -> Bool {
        if s.isPro { return true }
        if s.userOptedOut && s.hasSeenDay35 { return true }
        // past the Day 49 cutoff — give up regardless of whether [G] was shown
        if s.daysSinceTrialStart >= 48 { return true }
        // all events shown
        if s.hasSeenWelcome && s.hasSeenDay12 && s.hasSeenDay35 &&
           (s.hasSeenProactiveDay15 || s.hasSeenFullUpgrade) && s.hasSeenDay21 { return true }
        return false
    }

    /// Check if a given hour:minute falls within the allowed time windows (10:00-11:30 or 15:30-17:00)
    static func isInTimeWindow(hour: Int, minute: Int) -> Bool {
        let totalMinutes = hour * 60 + minute
        return (totalMinutes >= 600 && totalMinutes <= 690) || // 10:00-11:30
               (totalMinutes >= 930 && totalMinutes <= 1020)   // 15:30-17:00
    }
}
