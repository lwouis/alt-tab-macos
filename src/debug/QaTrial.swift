#if DEBUG
import Cocoa

/// The QA menu's trial journey. The license is the in-memory overlay of `LicenseManager.mockTrialDay`, so the
/// Keychain and the real trial start are never touched. Time is a ticking offset on the shared clock
/// (`QaLifecycleEnvironment.menuClockOffset`), so the real scheduler and its timers run. The Pro-transition
/// flags live in the real license defaults suite, and the expiry downgrade can change the style preferences;
/// `reset()` restores those.
enum QaTrial {
    struct Scenario {
        let title: String
        /// The step the tester takes next, shown in the menu's status line.
        let next: String
        let run: () -> Void
    }

    /// The trial history the Pro journey reads in place of `UsageStats` (`UsageStats.qaEvidence`).
    struct History {
        var searches: Int? = 37
        var style = AppearanceStylePreference.appIcons
        var extraShortcuts: Int? = 12
        var autoSize = true
        /// The feature of the last blocked attempt: the expiration and Day 35 popovers open on its tab.
        var attempted: ProJourneyFeature?

        var evidence: ProJourneyEvidence {
            ProJourneyEvidence(searches: searches, extraShortcuts: extraShortcuts,
                               adoptedStyle: style == .thumbnails ? nil : style.index, usedAuto: autoSize)
        }
    }

    static var history = History()
    static var nextStep = ""
    static let days = [1, 2, 4, 5, 6, 11, 12, 13, 14, 15, 16, 21, 34, 35, 36, 49]
    static let times = [(9, 59), (10, 0), (11, 31), (13, 0), (15, 29), (15, 30), (17, 1)]

    static let scenarioSections: [(String, [Scenario])] = [
        ("During the trial", [
            Scenario(title: "Day 1 · Welcome letter (upgrading user)", next: "The letter opens now") {
                start(day: 1)
            },
            Scenario(title: "Day 1 · Onboarding (new user)", next: "Use the shortcut it shows; Settings opens after") {
                start(day: 1)
                ProTransitionManager.shared.hasSeenWelcome = true
                if OnboardingPopover.show(announcesTrial: true) {
                    ProTransitionManager.shared.state.onboardingInProgress = true
                }
            },
            Scenario(title: "Day 4 · Style tour", next: "Alt-Tab and release: the tour follows 1 s later (shortcut 1 must use Thumbnails)") {
                start(day: 4)
            },
            Scenario(title: "Day 6 · Search tip", next: "Alt-Tab and keep holding for 1 s") {
                start(day: 6)
                SearchDiscoveryHint.shared.showForQA()
            },
            Scenario(title: "Day 6 · Extra-shortcut tip", next: "Alt-Tab and keep holding for 1 s (needs shortcut 2 on the active app with the same hold key, else the Search tip shows)") {
                start(day: 6)
                SearchDiscoveryHint.shared.showForQA(extraShortcut: true)
            },
            Scenario(title: "Day 13 · Menu bar badge", next: "The menu bar icon shows the badge") {
                start(day: 13)
            },
            Scenario(title: "Day 14 · Trial ends in 1 minute, AltTab still running", next: "Wait a minute, then Alt-Tab: last Pro session, then the trial-ended popover") {
                start(day: 14)
                QaLifecycleEnvironment.menuClockOffset += 86400 - 60
                ProTransitionManager.shared.onAppLaunchComplete()
            },
        ]),
        ("After the trial", [
            Scenario(title: "Day 15 · Last Pro session, then the trial-ended popover", next: "Alt-Tab: still Pro once; release: the popover opens on the tab the history favors") {
                start(day: 15)
            },
            Scenario(title: "Day 15 · Blocked Search opens the popover on Search", next: "Alt-Tab, then press the Search key") {
                start(day: 15) { $0.freePassUsed = true; $0.hasTriggeredPostExpirationSwitcher = true }
            },
            Scenario(title: "Day 16 · Blocked Search popover", next: "Alt-Tab, then press the Search key") {
                start(day: 16, announced: true)
            },
            Scenario(title: "Day 35 · Final reminder after a recent attempt", next: "Alt-Tab and release: the reminder follows 1 s later, on the attempted feature") {
                start(day: 35, announced: true)
                ProTransitionManager.shared.state.recordIntent(history.attempted ?? .search)
            },
            Scenario(title: "Day 35 · No recent attempt", next: "Alt-Tab and release: nothing appears") {
                start(day: 35, announced: true)
            },
        ]),
        ("License", [
            Scenario(title: "Activation celebration", next: "") { ProActivationPopover.show() },
            Scenario(title: "Pro user", next: "Every Pro feature works; no prompt appears") {
                QaLifecycle.closeSurfaces()
                LicenseManager.shared.mockProUser()
            },
        ]),
    ]

    static let surfaceSections: [(String, [(String, () -> Void)])] = [
        ("Trial", [
            ("Welcome letter (new user)", { welcome(freshInstall: true) }),
            ("Welcome letter (upgrading user)", { welcome(freshInstall: false) }),
            ("Onboarding: press the shortcut", { OnboardingPopover.showForQa(completion: false) }),
            ("Onboarding: That's it", { OnboardingPopover.showForQa(completion: true) }),
            ("Day 4 style tour", { Day4TourPopover.show() }),
        ]),
        ("After the trial", [
            ("Blocked Search", { Day15HardGatePopover.show(for: .feature(.searchInSwitcher)) }),
            ("Blocked extra shortcut", { Day15HardGatePopover.show(for: .feature(.extraShortcut(index: 1))) }),
            ("Blocked App Icons", { Day15HardGatePopover.show(for: .proPreferences(appearanceStyle: .appIcons, shortcut: false)) }),
            ("Blocked Titles", { Day15HardGatePopover.show(for: .proPreferences(appearanceStyle: .titles, shortcut: false)) }),
            ("Blocked, generic", { Day15HardGatePopover.show(for: nil) }),
        ]),
        ("Other", [
            ("Activation celebration", { ProActivationPopover.show() }),
            ("Can't save settings: symlink", { PreferencesPersistenceCheck.debugShowDialog(symlinked: true) }),
            ("Can't save settings: unwritable", { PreferencesPersistenceCheck.debugShowDialog(symlinked: false) }),
        ]),
    ]

    static func play(_ scenario: Scenario) {
        scenario.run()
        nextStep = scenario.next
    }

    /// Like a user absent since the previous prompt: prompts before `day` are marked seen.
    /// `announced` adds a consumed free pass and a delivered expiration announcement.
    static func start(day: Int, at time: (Int, Int)? = nil, announced: Bool = false,
                      _ customize: (ProTransitionManager) -> Void = { _ in }) {
        QaLifecycle.closeSurfaces()
        App.hideUi()
        let manager = ProTransitionManager.shared
        manager.resetAllState()
        ProTransitionState.markFreshInstallIfUnknown(false)
        let now = Calendar.current.dateComponents([.hour, .minute], from: LicenseManager.shared.clock.now)
        setClock(time ?? (now.hour!, now.minute!))
        manager.hasSeenWelcome = day > 1
        manager.hasSeenDay4Tour = day > 4
        if announced {
            manager.freePassUsed = true
            manager.hasTriggeredPostExpirationSwitcher = true
            manager.state.hasSeenFullUpgrade = true
        }
        customize(manager)
        LicenseManager.shared.mockTrialDay(day)
        UsageStats.qaEvidence = history.evidence
        Menubar.menubarIconCallback(nil)
        manager.onAppLaunchComplete()
    }

    /// The clock jumps to that time today; the trial day follows from the mocked trial start.
    static func setClock(_ time: (Int, Int)) {
        let now = Date()
        let target = Calendar.current.date(bySettingHour: time.0, minute: time.1, second: 0, of: now)!
        QaLifecycleEnvironment.menuClockOffset = target.timeIntervalSince(now)
    }

    /// Keeps every flag, like the same user coming back a day later. Due timers fire, as at launch.
    static func nextDay() {
        QaLifecycleEnvironment.menuClockOffset += 86400
        LicenseManager.shared.refreshState()
        Menubar.menubarIconCallback(nil)
        ProTransitionManager.shared.onAppLaunchComplete()
        nextStep = ""
    }

    static func reset() {
        QaLifecycle.closeSurfaces()
        ProTransitionManager.shared.resetAllState()
        QaLifecycleEnvironment.menuClockOffset = 0
        UsageStats.qaEvidence = nil
        nextStep = ""
        LicenseManager.shared.refreshState()
        Menubar.menubarIconCallback(nil)
    }

    // MARK: - The four-tab popover, with the history above

    static func showTrialEnded() {
        Day15FullUpgradeWindow.shared?.close()
        if LicenseManager.shared.isProAvailable { LicenseManager.shared.mockTrialDay(15) }
        UsageStats.qaEvidence = history.evidence
        Day15FullUpgradeWindow.show(for: history.attempted.map(attempt))
    }

    static func showDay35() {
        Day35FinalWindow.shared?.close()
        if LicenseManager.shared.isProAvailable { LicenseManager.shared.mockTrialDay(35) }
        UsageStats.qaEvidence = history.evidence
        ProTransitionManager.shared.state.recordIntent(history.attempted ?? .search)
        Day35FinalWindow.show()
    }

    static func showSettings() {
        UsageStats.qaEvidence = history.evidence
        UpgradeTab.showForQa(history.attempted)
    }

    private static func attempt(_ feature: ProJourneyFeature) -> HardGateReason {
        switch feature {
            case .search: return .feature(.searchInSwitcher)
            case .styles: return .feature(.appIconsAndTitlesStyle)
            case .shortcuts: return .feature(.extraShortcut(index: 1))
            case .autoSize: return .feature(.autoSize)
        }
    }

    private static func welcome(freshInstall: Bool) {
        Day1WelcomeLetterPopover.show(forceFreshInstall: freshInstall)
    }

    // MARK: - Status

    static var status: String {
        let license = LicenseManager.shared
        let manager = ProTransitionManager.shared
        let state = manager.currentState()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        let day = license.trialDay.map { "Day \($0)" } ?? "No trial"
        var lines = ["\(day) · \(formatter.string(from: license.clock.now)) · \(licenseLabel(license.state))"]
        lines.append("Next Alt-Tab: " + nextSession(state))
        let next = ProTransitionState.defaults.double(forKey: "proTransition.nextScheduledDate")
        let badge = manager.shouldShowBadgeDot ? " · badge on" : ""
        lines.append("Timer: " + (next > 0 ? formatter.string(from: Date(timeIntervalSince1970: next)) : "none") + badge)
        lines.append("Seen: " + seen(state))
        lines.append("Next: " + (nextStep.isEmpty ? "play a scenario, or Go to a day" : nextStep))
        return lines.joined(separator: "\n")
    }

    private static func licenseLabel(_ state: LicenseState) -> String {
        switch state {
            case .trialNotStarted: return "setup pending"
            case let .trial(daysRemaining): return "trial, \(daysRemaining) days left"
            case .trialExpired: return "trial ended"
            case .proExpired: return "license too old"
            case .pro: return "Pro"
        }
    }

    private static func nextSession(_ state: ProTransitionManagerTestable.State) -> String {
        if let pending = ProTransitionManager.shared.pendingPromptForQa { return pendingLabel(pending) + " queued for 1 s after release" }
        switch ProTransitionManagerTestable.evaluateSwitcherOpen(state) {
            case .showDay4Tour: return "style tour after release"
            case .showDay35Final: return "final reminder after release"
            case .showExpiration: return "trial-ended popover after release"
            case .triggerFreePass: return "last Pro session, then the trial-ended popover"
            case .noop: return "nothing"
        }
    }

    private static func pendingLabel(_ action: PendingDismissAction) -> String {
        switch action {
            case .showFullUpgrade: return "trial-ended popover"
            case .showDay4Tour: return "style tour"
            case .showDay35Final: return "final reminder"
        }
    }

    private static func seen(_ s: ProTransitionManagerTestable.State) -> String {
        let flags = [(s.hasSeenWelcome, "welcome"), (s.hasSeenDay4Tour, "tour"),
                     (s.freePassUsed, "free pass"), (s.hasSeenFullUpgrade || s.hasSeenProactiveDay15, "trial ended"),
                     (s.hasSeenDay35, "day 35"), (s.messageShownToday, "message today"),
                     (s.recentIntent, "recent attempt"), (s.userOptedOut, "opted out")]
        let names = flags.filter(\.0).map(\.1)
        return names.isEmpty ? "nothing" : names.joined(separator: ", ")
    }
}
#endif
