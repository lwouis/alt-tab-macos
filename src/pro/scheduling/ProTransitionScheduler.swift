import Foundation

/// Schedules the timed Pro-transition prompts ([A] Welcome, [B] Day 12, [D] Day 15, [F] Day 21,
/// [G] Day 35). Owns the persisted `nextScheduledDate`, the in-flight `DispatchWorkItem`, and the
/// `computeNextFireDate` logic that walks the remaining unshown prompts. Fires a caller-supplied
/// closure when the time arrives; the coordinator decides what to show.
class ProTransitionScheduler {
    private let defaults: UserDefaults
    private let licenseManager: LicenseManager
    private let state: ProTransitionState
    private let onFire: () -> Void
    private var workItem: DispatchWorkItem?

    private static let nextScheduledDateKey = "proTransition.nextScheduledDate"

    init(defaults: UserDefaults, licenseManager: LicenseManager, state: ProTransitionState, onFire: @escaping () -> Void) {
        self.defaults = defaults
        self.licenseManager = licenseManager
        self.state = state
        self.onFire = onFire
    }

    /// Fire now if a missed wake-up was persisted, then schedule the next one.
    func onAppLaunchComplete() {
        let saved = defaults.double(forKey: Self.nextScheduledDateKey)
        if saved > 0 && Date(timeIntervalSince1970: saved) <= Date() {
            onFire()
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
        let delay = max(0, fireDate.timeIntervalSinceNow)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onFire()
            self.scheduleNext()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Compute the next date when a time-based prompt should fire.
    func computeNextFireDate() -> Date? {
        if case .pro = licenseManager.state { return nil }
        if state.userOptedOut && state.hasSeenDay35 { return nil }
        guard let trialStart = licenseManager.trialStartDate else { return nil }

        // Day 1: Welcome (immediate)
        if !state.hasSeenWelcome {
            return Date()
        }

        var candidates = [Date]()

        // Day 12: 10:00 or 15:30 — single calendar day, drop the candidate once daysSinceTrialStart >= 12
        if !state.hasSeenDay12 {
            let day13Start = trialStart.addingTimeInterval(12 * 86400)
            if let d = nextTimeWindow(onOrAfterDay: 11, trialStart: trialStart), d < day13Start {
                candidates.append(d)
            }
        }

        // Day 15+: Proactive (only if no hard-gate happened)
        if !state.hasSeenProactiveDay15 && !state.hasSeenFullUpgrade {
            if let d = nextTimeWindow(onOrAfterDay: 14, trialStart: trialStart) {
                candidates.append(d)
            }
        }

        // Day 21+: Reminder (skip once Day 35 shown)
        if !state.hasSeenDay21 && !state.hasSeenDay35 {
            if let d = nextTimeWindow(onOrAfterDay: 20, trialStart: trialStart) {
                candidates.append(d)
            }
        }

        // Day 35+: Final (give up at Day 49)
        if !state.hasSeenDay35 && !state.userOptedOut {
            if let d = nextTimeWindow(onOrAfterDay: 34, trialStart: trialStart) {
                let day49 = trialStart.addingTimeInterval(48 * 86400)
                if d < day49 {
                    candidates.append(d)
                }
            }
        }

        return candidates.min()
    }

    /// Find the next 10:00 or 15:30 that falls on or after the given trial day.
    private func nextTimeWindow(onOrAfterDay trialDay: Int, trialStart: Date) -> Date? {
        let cal = Calendar.current
        let now = Date()
        let targetDate = trialStart.addingTimeInterval(Double(trialDay) * 86400)
        let startDate = max(targetDate, now)

        for dayOffset in 0..<60 {
            let candidateDay = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: startDate))!
            for slot in [(hour: 10, minute: 0), (hour: 15, minute: 30)] {
                if let candidate = cal.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: candidateDay) {
                    if candidate >= now && candidate >= targetDate {
                        return candidate
                    }
                }
            }
        }
        return nil
    }
}
