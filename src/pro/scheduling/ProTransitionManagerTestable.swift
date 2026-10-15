import Foundation

/// Pure decision logic for the Pro transition state machine.
/// No singletons, no Date(), no UI, no side effects — just inputs → outputs.
/// This makes the complex state machine fully unit-testable.
enum ProTransitionManagerTestable {

    // MARK: - State snapshot (all inputs the decisions depend on)

    struct State {
        var isAwaitingTrial = false
        var isPro: Bool
        var isTrialActive: Bool // true for .trial, false for .trialExpired
        var daysSinceTrialStart: Int // 0-indexed: Day 1 = 0, Day 15 = 14
        var hasSeenWelcome: Bool
        var hasSeenDay4Tour: Bool
        /// The Day 4 tour was queued and has not yet acknowledged visible presentation.
        var day4TourDeferred = false
        var freePassUsed: Bool
        var hasSeenFullUpgrade: Bool
        var hasSeenProactiveDay15: Bool
        var hasSeenDay35: Bool
        var userOptedOut: Bool
        var hasTriggeredPostExpirationSwitcher: Bool
        var usesThumbnails = true
        var recentIntent = false
        var messageShownToday = false

        // periphery:ignore - the factory every ProTransitionTests case starts from
        static func fresh() -> State {
            State(isPro: false, isTrialActive: true, daysSinceTrialStart: 0,
                  hasSeenWelcome: false, hasSeenDay4Tour: false, freePassUsed: false,
                  hasSeenFullUpgrade: false, hasSeenProactiveDay15: false,
                  hasSeenDay35: false,
                  userOptedOut: false,
                  hasTriggeredPostExpirationSwitcher: false)
        }
    }

    // MARK: - Action enums (outputs)

    enum TimedAction: Equatable {
        case showWelcome          // [A]
        case showDay35Final       // [G]
        case none
    }

    enum HardGateAction: Equatable {
        case unavailable          // setup is unresolved; no free pass or purchase prompt
        case allow                // pro or trial active
        case freePass             // first hard-gate after expiry — allow once, then show [C]
        case showFullUpgrade      // [C]
        case showHardGatePopover  // [E] — shown on every post-[C] hard-gate attempt
    }

    /// What should happen when the switcher is opened (a fresh summon, not a cycle)?
    enum SwitcherOpenAction: Equatable {
        case showDay4Tour          // [H] — fires once on Day 4
        case showDay35Final
        case showExpiration
        case triggerFreePass       // post-expiration first summon when a Pro style or shortcut was configured
        case noop
    }

    // MARK: - Pure decision functions

    /// What should happen on a timed evaluation (scheduler fire or app launch)?
    static func evaluateTimedAction(_ s: State) -> TimedAction {
        if s.isAwaitingTrial || s.isPro || !s.isTrialActive || s.userOptedOut { return .none }

        // Day 1: Welcome letter
        if !s.hasSeenWelcome {
            return .showWelcome
        }

        return .none
    }

    /// The scheduler's next trial deadline: the start of the badge days, then the trial's end. Days are 24-hour
    /// steps from the trial start; the extra second lands each deadline inside its day.
    static func nextTrialDeadline(after now: Date, trialStart: Date) -> Date? {
        [badgeDotDays.lowerBound, LicenseManager.trialDuration]
            .map { trialStart.addingTimeInterval(Double($0) * 86400 + 1) }
            .first { $0 > now }
    }

    /// What should happen when a hard-gated feature is attempted?
    static func evaluateHardGate(_ s: State) -> HardGateAction {
        if s.isAwaitingTrial { return .unavailable }
        if s.isPro || s.isTrialActive { return .allow }
        if !s.freePassUsed { return .freePass }
        if !s.hasSeenFullUpgrade && !s.hasSeenProactiveDay15 { return .showFullUpgrade }
        return .showHardGatePopover
    }

    /// Fresh-session opportunities are presented only after dismissal. An interrupted expiration
    /// announcement remains eligible; an interrupted Day 35 reminder retries only on that day. Day 4 consumes
    /// its first session unless the tour could not be presented: it then waits for a later session, on Day 4 or 5.
    /// A user absent on Day 4 gets no Day 5 catch-up.
    static func evaluateSwitcherOpen(_ s: State) -> SwitcherOpenAction {
        if s.isAwaitingTrial || s.isPro { return .noop }
        if s.isTrialActive {
            let firstDay4Session = s.daysSinceTrialStart == 3 && !s.hasSeenDay4Tour
            let blockedEarlier = s.day4TourDeferred && day4TourDays.contains(s.daysSinceTrialStart)
            if (firstDay4Session || blockedEarlier) && s.usesThumbnails && !s.userOptedOut &&
                !s.messageShownToday { return .showDay4Tour }
            return .noop
        }
        // Trial expired: trigger free-pass + [C] on first summon, regardless of which Pro features were
        // configured. For users with no remembered* values, the reason resolves to `.nonEngaged` and the
        // free-pass session is a harmless no-op (read() falls back to stored Free defaults).
        if !s.hasTriggeredPostExpirationSwitcher && !s.freePassUsed {
            return .triggerFreePass
        }
        if !s.hasSeenFullUpgrade && !s.hasSeenProactiveDay15 && !s.userOptedOut {
            return .showExpiration
        }
        if s.daysSinceTrialStart == 34 && !s.hasSeenDay35 && !s.userOptedOut && s.recentIntent &&
            !s.messageShownToday {
            return .showDay35Final
        }
        return .noop
    }

    /// Focusing a window on another Space changes the active Space during the delay between dismissal and a
    /// queued prompt. That move is the switch the user asked for, so the prompt follows them to that Space.
    /// While the switcher is open, or with nothing armed, a Space change still cancels.
    static func spaceChangeCancelsPendingPrompt(switcherIsShown: Bool, awaitingDismissalDelay: Bool) -> Bool {
        switcherIsShown || !awaitingDismissalDelay
    }

    /// Days 4 and 5, zero-based.
    static let day4TourDays = 3 ... 4

    /// Days 13 and 14, zero-based.
    static let badgeDotDays = 12 ... 13

    /// Should the menubar icon show a badge dot?
    /// Pro users never see the badge — spec: "Purchase at any point → all indicators cleared."
    static func shouldShowBadgeDot(_ s: State) -> Bool {
        !s.isAwaitingTrial && !s.isPro && s.isTrialActive && badgeDotDays.contains(s.daysSinceTrialStart)
    }
}

/// Local evidence only. Missing or pruned history cannot be interpreted as zero usage.
enum ProJourneyFeature: String, CaseIterable {
    case search, styles, shortcuts, autoSize
}

struct ProJourneyEvidence {
    var searches: Int?
    var extraShortcuts: Int?
    var adoptedStyle: Int?
    var usedAuto: Bool?

    /// Unknown history and a count of zero both read as unused: no tab claims use that did not happen.
    func used(_ feature: ProJourneyFeature) -> Bool {
        switch feature {
        case .search: return (searches ?? 0) > 0
        case .styles: return adoptedStyle != nil
        case .shortcuts: return (extraShortcuts ?? 0) > 0
        case .autoSize: return usedAuto == true
        }
    }

    /// Adopted style, then repeated actions by count (Search breaks ties), then Auto, then single use.
    /// Counts measure actions, not success or value. Explicit requests always override this fallback.
    func openingFeature(requested: ProJourneyFeature?) -> ProJourneyFeature {
        requested ?? preferredFeature
    }

    var preferredFeature: ProJourneyFeature {
        if adoptedStyle != nil { return .styles }
        let searchCount = searches ?? 0
        let shortcutCount = extraShortcuts ?? 0
        if max(searchCount, shortcutCount) >= 2 {
            return shortcutCount > searchCount ? .shortcuts : .search
        }
        if usedAuto == true { return .autoSize }
        return ProJourneyFeature.allCases.first(where: used) ?? .autoSize
    }

    static func count(_ timestamps: [Int]?, start: Date?, end: Date?, now: Date) -> Int? {
        guard let timestamps, let start, let end, end >= start,
              start >= now.addingTimeInterval(-365 * 86400),
              timestamps.allSatisfy({ $0 >= 0 }) else { return nil }
        return timestamps.filter {
            $0 >= Int(start.timeIntervalSince1970) && $0 < Int(end.timeIntervalSince1970) &&
                $0 <= Int(now.timeIntervalSince1970)
        }.count
    }

    /// The style and size the trial last used, captured once before the downgrade. Thumbnails (index 0) is
    /// the free style, so it adopts nothing. An install an earlier version already downgraded has lost its
    /// overrides, so it claims nothing at all and the journey shows generic examples.
    static func capture(styleIndex: Int, autoSize: Bool, previouslyDowngraded: Bool) -> (adoptedStyle: Int?, usedAuto: Bool?) {
        guard !previouslyDowngraded else { return (nil, nil) }
        return (styleIndex == 0 ? nil : styleIndex, autoSize)
    }

    /// A shortcut removed since the trial falls back to the first one.
    static func captureShortcutIndex(_ lastUsed: Int, shortcutCount: Int) -> Int {
        (0 ..< shortcutCount).contains(lastUsed) ? lastUsed : 0
    }

    /// A message dated in the future (the clock was set back) also counts, rather than allowing a second one.
    static func isMessageToday(_ last: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let last else { return false }
        return calendar.isDate(last, inSameDayAs: now) || last > now
    }

    static func hasRecentIntent(at date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return (0 ... 7 * 86400).contains(now.timeIntervalSince(date))
    }
}
