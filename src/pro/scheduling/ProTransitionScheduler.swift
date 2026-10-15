import Foundation

/// Owns the single timed wake-up for Welcome, the trial's badge days and the end of the trial. Other prompts
/// follow switcher dismissal. The coordinator rechecks eligibility when this scheduler fires.
class ProTransitionScheduler {
    private let defaults: UserDefaults
    private let licenseManager: LicenseManager
    private let state: ProTransitionState
    private let onFire: () -> Void
    private var workItem: DispatchWorkItem?
    private var attemptedWelcome = false

    private static let nextScheduledDateKey = "proTransition.nextScheduledDate"

    init(defaults: UserDefaults, licenseManager: LicenseManager, state: ProTransitionState, onFire: @escaping () -> Void) {
        self.defaults = defaults
        self.licenseManager = licenseManager
        self.state = state
        self.onFire = onFire
    }

    /// Fire now if a missed wake-up was persisted, then schedule the next one.
    func onAppLaunchComplete() {
        guard licenseManager.state != .trialNotStarted, !state.onboardingInProgress else { cancel(); return }
        let saved = defaults.double(forKey: Self.nextScheduledDateKey)
        if saved > 0 && Date(timeIntervalSince1970: saved) <= licenseManager.clock.now {
            fire()
        }
        scheduleNext()
    }

    /// Cancel any pending work and clear the persisted date — e.g. when the user purchases Pro.
    func cancel() {
        defaults.removeObject(forKey: Self.nextScheduledDateKey)
        workItem?.cancel()
        workItem = nil
    }

    /// Compute the next fire date and arm a single `DispatchWorkItem`. Reschedules itself after firing.
    func scheduleNext() {
        workItem?.cancel()
        guard let fireDate = computeNextFireDate() else {
            defaults.removeObject(forKey: Self.nextScheduledDateKey)
            return
        }
        defaults.set(fireDate.timeIntervalSince1970, forKey: Self.nextScheduledDateKey)
        let delay = max(0, fireDate.timeIntervalSince(licenseManager.clock.now))
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            fire()
            scheduleNext()
        }
        workItem = item
        // Wall time keeps counting while the Mac sleeps; `deadline:` would push the trial's end back by every
        // night the Mac spent asleep. A wall deadline that passed during sleep fires on wake.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + delay, execute: item)
    }

    private func fire() {
        attemptedWelcome = true
        onFire()
    }

    /// Compute the next date when a time-based prompt should fire.
    func computeNextFireDate() -> Date? {
        if case .pro = licenseManager.state { return nil }
        if state.onboardingInProgress { return nil }
        guard let start = licenseManager.trialStartDate else { return nil }
        // Welcome is immediate; the badge and expiry deadlines remain independent of promotional prompts.
        if case .trial = licenseManager.state, !state.userOptedOut && !state.hasSeenWelcome && !attemptedWelcome {
            return licenseManager.clock.now
        }
        guard case .trial = licenseManager.state else { return nil }
        return ProTransitionManagerTestable.nextTrialDeadline(after: licenseManager.clock.now, trialStart: start)
    }

    #if DEBUG
    func resetForQa() {
        attemptedWelcome = false
    }
    #endif
}
