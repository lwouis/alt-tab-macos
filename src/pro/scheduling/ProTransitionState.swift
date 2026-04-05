import Foundation

/// Persisted state for the Pro-transition flow. Owns all `hasSeen…` flags and the `remembered*`
/// indices plus the preference snapshot/restore logic those indices drive. Snapshots itself into
/// `ProTransitionManagerTestable.State` for the pure decision logic to consume.
///
/// Storage: `LicenseManager.defaultsSuiteName` suite, keys prefixed `proTransition.`.
class ProTransitionState {
    static let defaults = UserDefaults(suiteName: LicenseManager.defaultsSuiteName)!

    // MARK: - Persisted Day-X flags

    var hasSeenWelcome: Bool { get { Self.bool("hasSeenWelcome") } set { Self.set("hasSeenWelcome", newValue) } }
    var hasSeenDay4Tour: Bool { get { Self.bool("hasSeenDay4Tour") } set { Self.set("hasSeenDay4Tour", newValue) } }
    var hasSeenDay12: Bool { get { Self.bool("hasSeenDay12") } set { Self.set("hasSeenDay12", newValue) } }
    var freePassUsed: Bool { get { Self.bool("freePassUsed") } set { Self.set("freePassUsed", newValue) } }
    var hasSeenFullUpgrade: Bool { get { Self.bool("hasSeenFullUpgrade") } set { Self.set("hasSeenFullUpgrade", newValue) } }
    var hasSeenProactiveDay15: Bool { get { Self.bool("hasSeenProactiveDay15") } set { Self.set("hasSeenProactiveDay15", newValue) } }
    var hasSeenDay21: Bool { get { Self.bool("hasSeenDay21") } set { Self.set("hasSeenDay21", newValue) } }
    var hasSeenDay35: Bool { get { Self.bool("hasSeenDay35") } set { Self.set("hasSeenDay35", newValue) } }
    var userOptedOut: Bool { get { Self.bool("userOptedOut") } set { Self.set("userOptedOut", newValue) } }
    var hasTriggeredPostExpirationSwitcher: Bool { get { Self.bool("hasTriggeredPostExpirationSwitcher") } set { Self.set("hasTriggeredPostExpirationSwitcher", newValue) } }

    static var isFreshInstall: Bool { Self.bool("isFreshInstall") }

    /// Persists the fresh-install signal from `PreferencesMigrations.migratePreferences()` (which is
    /// the only place that can still observe nil `preferencesVersion`). Idempotent: only writes the
    /// first time, so re-running migration on subsequent launches doesn't reclassify the user.
    static func markFreshInstallIfUnknown(_ value: Bool) {
        guard Self.defaults.object(forKey: "proTransition.isFreshInstall") == nil else { return }
        Self.defaults.set(value, forKey: "proTransition.isFreshInstall")
    }

    // MARK: - Remembered Pro indices (for ghost UI + restoration on unlock)

    var rememberedAppearanceStyle: Int? {
        get { Self.int(ProGatedPreferences.appearanceStyle.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.appearanceStyle.gate!.rememberedKey, newValue) }
    }
    var rememberedAppearanceSize: Int? {
        get { Self.int(ProGatedPreferences.appearanceSize.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.appearanceSize.gate!.rememberedKey, newValue) }
    }
    var rememberedShortcutStyle: Int? {
        get { Self.int(ProGatedPreferences.shortcutStyle.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.shortcutStyle.gate!.rememberedKey, newValue) }
    }

    // Per-shortcut override remembered indices. Shortcut 0 is the only index reachable while
    // locked, so it's the only one we snapshot. Indices >= 1 are hard-gated at trigger time.
    var rememberedAppearanceStyleOverride: Int? {
        get { Self.int(ProGatedPreferences.appearanceStyleOverride0.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.appearanceStyleOverride0.gate!.rememberedKey, newValue) }
    }
    var rememberedAppearanceSizeOverride: Int? {
        get { Self.int(ProGatedPreferences.appearanceSizeOverride0.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.appearanceSizeOverride0.gate!.rememberedKey, newValue) }
    }
    var rememberedShortcutStyleOverride: Int? {
        get { Self.int(ProGatedPreferences.shortcutStyleOverride0.gate!.rememberedKey) }
        set { Self.setInt(ProGatedPreferences.shortcutStyleOverride0.gate!.rememberedKey, newValue) }
    }

    // MARK: - Snapshot / restore Pro preferences

    /// Snapshot the user's Pro-selected preferences and switch them to Free equivalents so the
    /// switcher and Settings UI render the locked experience immediately. Snapshots the Pro index
    /// into `remembered*` for two purposes: (1) drives the ghost outline in Settings, (2) is read
    /// back by `PreferenceDefinition.read()` during an active free-pass session so the user gets
    /// one last Pro switcher session before [C]. Called exactly once per user — the first time
    /// either [C] Day15 FullUpgrade or [D] Day15 Proactive is shown. Idempotent: re-entry is a
    /// no-op since stored values no longer match the Pro set after the first pass.
    func onProLockEngaged() {
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
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        return ProTransitionManagerTestable.State(
            isPro: { if case .pro = licenseState { return true }; return false }(),
            isTrialActive: licenseState.isProAvailable,
            daysSinceTrialStart: daysSinceTrialStart,
            isInTimeWindow: ProTransitionManagerTestable.isInTimeWindow(hour: hour, minute: minute),
            hasSeenWelcome: hasSeenWelcome,
            hasSeenDay4Tour: hasSeenDay4Tour,
            hasSeenDay12: hasSeenDay12,
            freePassUsed: freePassUsed,
            hasSeenFullUpgrade: hasSeenFullUpgrade,
            hasSeenProactiveDay15: hasSeenProactiveDay15,
            hasSeenDay21: hasSeenDay21,
            hasSeenDay35: hasSeenDay35,
            userOptedOut: userOptedOut,
            hasTriggeredPostExpirationSwitcher: hasTriggeredPostExpirationSwitcher
        )
    }

    // MARK: - QA / Debug

    #if DEBUG
    /// Remove all persisted Pro-transition flags and remembered indices. Caller is responsible
    /// for running `onProUnlocked()` first if the user had snapshotted Pro selections.
    func resetAll() {
        let flagKeys = ["hasSeenWelcome", "hasSeenDay4Tour", "hasSeenDay12", "freePassUsed", "hasSeenFullUpgrade",
                        "hasSeenProactiveDay15", "hasSeenDay21", "hasSeenDay35", "userOptedOut",
                        "hasTriggeredPostExpirationSwitcher", "isFreshInstall", "nextScheduledDate"]
        let rememberedKeys = ProGatedPreferences.all.map { $0.rememberedKey }
        (flagKeys + rememberedKeys).forEach { Self.defaults.removeObject(forKey: "proTransition.\($0)") }
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
