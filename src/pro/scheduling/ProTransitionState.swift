import Foundation

/// Persisted state for the Pro-transition flow. Owns all `hasSeen…` flags and the `remembered*`
/// indices plus the preference snapshot/restore logic those indices drive. Snapshots itself into
/// `ProTransitionManagerTestable.State` for the pure decision logic to consume.
///
/// Storage: `LicenseManager.defaultsSuiteName`, with `proTransition.` flags and local `proJourney.` evidence.
class ProTransitionState {
    var onboardingInProgress = false
    static let defaults = UserDefaults(suiteName: LicenseManager.defaultsSuiteName)!

    // MARK: - Persisted Day-X flags

    var hasSeenWelcome: Bool { get { Self.bool("hasSeenWelcome") } set { Self.set("hasSeenWelcome", newValue) } }
    var hasSeenDay4Tour: Bool { get { Self.bool("hasSeenDay4Tour") } set { Self.set("hasSeenDay4Tour", newValue) } }
    var day4TourDeferred: Bool { get { Self.bool("day4TourDeferred") } set { Self.set("day4TourDeferred", newValue) } }
    var freePassUsed: Bool { get { Self.bool("freePassUsed") } set { Self.set("freePassUsed", newValue) } }
    var hasSeenFullUpgrade: Bool { get { Self.bool("hasSeenFullUpgrade") } set { Self.set("hasSeenFullUpgrade", newValue) } }
    var hasSeenProactiveDay15: Bool { get { Self.bool("hasSeenProactiveDay15") } set { Self.set("hasSeenProactiveDay15", newValue) } }
    var hasSeenDay35: Bool { get { Self.bool("hasSeenDay35") } set { Self.set("hasSeenDay35", newValue) } }
    var userOptedOut: Bool { get { Self.bool("userOptedOut") } set { Self.set("userOptedOut", newValue) } }
    var hasTriggeredPostExpirationSwitcher: Bool { get { Self.bool("hasTriggeredPostExpirationSwitcher") } set { Self.set("hasTriggeredPostExpirationSwitcher", newValue) } }

    static var isFreshInstall: Bool { bool("isFreshInstall") }

    /// Persists the fresh-install signal from `PreferencesMigrations.migratePreferences()` (which is
    /// the only place that can still observe nil `preferencesVersion`). Idempotent: only writes the
    /// first time, so re-running migration on subsequent launches doesn't reclassify the user.
    static func markFreshInstallIfUnknown(_ value: Bool) {
        guard defaults.object(forKey: "proTransition.isFreshInstall") == nil else { return }
        defaults.set(value, forKey: "proTransition.isFreshInstall")
    }

    // MARK: - Remembered Pro indices (for ghost UI + restoration on unlock)

    var rememberedAppearanceStyle: Int? {
        get { Self.int(ProGatedPreferences.appearanceStyle.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.appearanceStyle.gate!.rememberedKey, newValue) }
    }
    var rememberedShortcutStyle: Int? {
        get { Self.int(ProGatedPreferences.shortcutStyle.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.shortcutStyle.gate!.rememberedKey, newValue) }
    }

    // MARK: - Snapshot / restore Pro preferences

    /// Capture adoption before downgrade. Remembered values drive the locked Settings outlines,
    /// the final free-pass session and restoration after activation. Re-entry is idempotent.
    func onProLockEngaged() {
        captureJourneyPreferences()
        for pref in ProGatedPreferences.all {
            if let storedIndex = pref.snapshotAndDowngrade() {
                Self.setInt(pref.rememberedKey, storedIndex)
            }
        }
    }

    /// Restore any remembered Pro values back to stored values. Called when the user upgrades to Pro.
    /// Restore writes with `notify: false` so `PreferencesEvents.preferenceChanged` doesn't fire while
    /// we're restoring — otherwise the `isProLocked && isStoredValuePro` check would yank the user to
    /// the Upgrade tab because the lock is still technically active during the restore pass.
    func onProUnlocked() {
        for pref in ProGatedPreferences.all {
            if let idx = Self.int(pref.rememberedKey) {
                pref.restoreFromIndex(idx)
                Self.setInt(pref.rememberedKey, nil)
            }
        }
    }

    // MARK: - Snapshot into the pure decision State

    /// Assemble a `ProTransitionManagerTestable.State` for the pure decision logic.
    func snapshot(licenseState: LicenseState, daysSinceTrialStart: Int, clock: Clock) -> ProTransitionManagerTestable.State {
        let now = clock.now
        return ProTransitionManagerTestable.State(
            isAwaitingTrial: licenseState == .trialNotStarted,
            isPro: { if case .pro = licenseState { return true }; return false }(),
            isTrialActive: licenseState.isProAvailable,
            daysSinceTrialStart: daysSinceTrialStart,
            hasSeenWelcome: hasSeenWelcome,
            hasSeenDay4Tour: hasSeenDay4Tour,
            day4TourDeferred: day4TourDeferred,
            freePassUsed: freePassUsed,
            hasSeenFullUpgrade: hasSeenFullUpgrade,
            hasSeenProactiveDay15: hasSeenProactiveDay15,
            hasSeenDay35: hasSeenDay35,
            userOptedOut: userOptedOut,
            hasTriggeredPostExpirationSwitcher: hasTriggeredPostExpirationSwitcher,
            usesThumbnails: Preferences.effectiveAppearanceStyle(0) == .thumbnails,
            recentIntent: ProJourneyEvidence.hasRecentIntent(
                at: Self.defaults.object(forKey: "proJourney.lastIntentAt") as? Date,
                now: now
            ),
            messageShownToday: messageShownToday(now)
        )
    }

    func messageShownToday(_ now: Date) -> Bool {
        ProJourneyEvidence.isMessageToday(Self.defaults.object(forKey: "proJourney.lastMessageAt") as? Date,
                                          now: now, calendar: .current)
    }

    func recordMessage() {
        Self.defaults.set(LicenseManager.shared.clock.now, forKey: "proJourney.lastMessageAt")
    }

    var lastIntent: ProJourneyFeature? {
        Self.defaults.string(forKey: "proJourney.lastIntent").flatMap(ProJourneyFeature.init(rawValue:))
    }

    func recordIntent(_ feature: ProJourneyFeature) {
        Self.defaults.set(feature.rawValue, forKey: "proJourney.lastIntent")
        Self.defaults.set(LicenseManager.shared.clock.now, forKey: "proJourney.lastIntentAt")
    }

    private func captureJourneyPreferences() {
        guard LicenseManager.shared.state == .trialExpired else { return }
        guard Self.defaults.object(forKey: "proJourney.preferencesCaptured") == nil else { return }
        let index = ProJourneyEvidence.captureShortcutIndex(Self.defaults.integer(forKey: "proJourney.lastTrialShortcut"),
                                                            shortcutCount: Preferences.shortcutCount)
        let styleKey = Preferences.hasOverride("appearanceStyleOverride", index)
            ? Preferences.indexToName("appearanceStyleOverride", index)
            : "appearanceStyle"
        let sizeKey = Preferences.hasOverride("appearanceSizeOverride", index)
            ? Preferences.indexToName("appearanceSizeOverride", index)
            : "appearanceSize"
        let style: AppearanceStylePreference = CachedUserDefaults.macroPref(
            styleKey,
            AppearanceStylePreference.allCases
        )
        let size: AppearanceSizePreference = CachedUserDefaults.macroPref(
            sizeKey,
            AppearanceSizePreference.allCases
        )
        let captured = ProJourneyEvidence.capture(styleIndex: style.index, autoSize: size == .auto,
            previouslyDowngraded: hasSeenFullUpgrade || hasSeenProactiveDay15 || rememberedAppearanceStyle != nil)
        if let adopted = captured.adoptedStyle { Self.defaults.set(adopted, forKey: "proJourney.adoptedStyle") }
        if let auto = captured.usedAuto { Self.defaults.set(auto, forKey: "proJourney.usedAuto") }
        Self.defaults.set(true, forKey: "proJourney.preferencesCaptured")
    }

    // MARK: - QA / Debug

    #if DEBUG
    /// Remove all persisted Pro-transition flags and remembered indices. Caller is responsible
    /// for running `onProUnlocked()` first if the user had snapshotted Pro selections.
    func resetAll() {
        let flagKeys = ["hasSeenWelcome", "hasSeenDay4Tour", "day4TourDeferred", "freePassUsed", "hasSeenFullUpgrade",
                        "hasSeenProactiveDay15", "hasSeenDay35", "userOptedOut",
                        "hasTriggeredPostExpirationSwitcher", "isFreshInstall", "nextScheduledDate"]
        let rememberedKeys = ProGatedPreferences.all.map(\.rememberedKey)
        (flagKeys + rememberedKeys).forEach { Self.defaults.removeObject(forKey: "proTransition.\($0)") }
        Self.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("proJourney.") }
            .forEach { Self.defaults.removeObject(forKey: $0) }
    }
    #endif

    // MARK: - UserDefaults helpers

    static func bool(_ key: String) -> Bool {
        defaults.bool(forKey: "proTransition.\(key)")
    }

    static func set(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: "proTransition.\(key)")
    }

    static func int(_ key: String) -> Int? {
        defaults.object(forKey: "proTransition.\(key)") as? Int
    }

    static func setInt(_ key: String, _ value: Int?) {
        if let value {
            defaults.set(value, forKey: "proTransition.\(key)")
        } else {
            defaults.removeObject(forKey: "proTransition.\(key)")
        }
    }
}
