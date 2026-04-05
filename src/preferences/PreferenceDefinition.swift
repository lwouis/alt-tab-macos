import Foundation

/// Gate policy for a Pro-degradable macro preference. Centralises:
/// - the free-tier equivalent to return when the user is Pro-locked,
/// - the `rememberedKey` under which the Pro value is snapshotted for later restore,
/// - the predicate identifying which stored values are "Pro".
struct PreferenceGate<T: MacroPreference & CaseIterable & Equatable> {
    let freeEquivalent: T
    let rememberedKey: String
    let isProValue: (T) -> Bool
}

/// Single-source-of-truth declaration for a macro preference: its key, default, and optional
/// Pro gate. Both the read-side (downgrade-on-lock) and the write-side (snapshot + restore)
/// go through this one definition — eliminating the duplicated Pro-gating logic that previously
/// lived in both `Preferences.swift` getters and `ProFeature.snapshotAndDowngradeStored` /
/// `restoreStored`.
struct PreferenceDefinition<T: MacroPreference & CaseIterable & Equatable> {
    let key: String
    let `default`: T
    let gate: PreferenceGate<T>?

    /// Read the currently-stored value, applying the gate if Pro is locked. The read passes
    /// through `CachedUserDefaults` so it's cheap on the hot path.
    ///
    /// Three branches when locked:
    /// 1. Free-pass session active and a remembered Pro index exists → return the remembered
    ///    Pro selection so the switcher renders the user's Pro choice for one last session.
    /// 2. Stored value is still a Pro value (transient, between lock and `onProLockEngaged()`) →
    ///    return the free equivalent.
    /// 3. Otherwise → return stored, which has been downgraded to the free equivalent already.
    func read() -> T {
        let stored: T = CachedUserDefaults.macroPref(key, Array(T.allCases))
        guard let gate = gate, LicenseManager.shared.isProLocked else { return stored }
        if ProTransitionManager.shared.isFreePassSessionActive,
           let rememberedIdx = ProTransitionState.int(gate.rememberedKey),
           Array(T.allCases).indices.contains(rememberedIdx) {
            return Array(T.allCases)[rememberedIdx]
        }
        if gate.isProValue(stored) {
            return gate.freeEquivalent
        }
        return stored
    }

    /// If the stored value is currently a Pro selection, overwrite it with the free equivalent
    /// and return its original index — the caller persists this index under `gate.rememberedKey`
    /// so the ghost UI signals the original choice and so a free-pass session can read it back
    /// in `read()`. Returns nil if no gate, or if already at the free value.
    /// Notifies observers (so Settings rows re-render immediately on lock).
    func snapshotAndDowngrade() -> Int? {
        guard let gate = gate else { return nil }
        let stored: T = CachedUserDefaults.macroPref(key, Array(T.allCases))
        guard gate.isProValue(stored) else { return nil }
        Preferences.set(key, gate.freeEquivalent.indexAsString)
        return stored.index
    }

    /// Restore the stored value from a remembered index. Writes with `notify: false` so the
    /// restore pass doesn't bounce observers to Upgrade while the lock is still technically active.
    /// No-op if the index is out of range for the enum.
    func restore(from rememberedIndex: Int) {
        guard Array(T.allCases).indices.contains(rememberedIndex) else { return }
        Preferences.set(key, String(rememberedIndex), false)
    }

    /// True when the stored value is a Pro selection, regardless of current lock state. Used by
    /// `PreferencesEvents.preferenceChanged` to decide whether a setter should bounce to Upgrade.
    func isStoredValuePro() -> Bool {
        guard let gate = gate else { return false }
        let stored: T = CachedUserDefaults.macroPref(key, Array(T.allCases))
        return gate.isProValue(stored)
    }
}

/// Type-erased view of a `PreferenceDefinition` that exposes only the operations whose return
/// types are already concrete (Int indices, Bool). This is what `ProTransitionState` iterates
/// over when doing lock / unlock passes without caring about each preference's underlying type.
struct AnyProGatedPreference {
    let preferenceKey: String
    let rememberedKey: String
    let snapshotAndDowngrade: () -> Int?
    let restoreFromIndex: (Int) -> Void
    let isStoredValuePro: () -> Bool
}

extension PreferenceDefinition {
    var erased: AnyProGatedPreference {
        AnyProGatedPreference(
            preferenceKey: key,
            rememberedKey: gate?.rememberedKey ?? "",
            snapshotAndDowngrade: { self.snapshotAndDowngrade() },
            restoreFromIndex: { self.restore(from: $0) },
            isStoredValuePro: { self.isStoredValuePro() })
    }
}

/// Registry of every Pro-gated preference. Each entry is declared once here — no more parallel
/// lists in `Preferences.defaultValues`, `Preferences.<prop>` getter, `ProFeature.preferenceKey`,
/// `ProFeature.rememberedKey`, `ProFeature.snapshotAndDowngradeStored`, `ProFeature.restoreStored`,
/// `ProFeature.isStoredValuePro`.
enum ProGatedPreferences {
    static let appearanceStyle = PreferenceDefinition<AppearanceStylePreference>(
        key: "appearanceStyle",
        default: .thumbnails,
        gate: PreferenceGate(
            freeEquivalent: .thumbnails,
            rememberedKey: "rememberedAppearanceStyle",
            isProValue: { $0 != .thumbnails }))

    static let appearanceSize = PreferenceDefinition<AppearanceSizePreference>(
        key: "appearanceSize",
        default: .auto,
        gate: PreferenceGate(
            freeEquivalent: .medium,
            rememberedKey: "rememberedAppearanceSize",
            isProValue: { $0 == .auto }))

    static let shortcutStyle = PreferenceDefinition<ShortcutStylePreference>(
        key: "shortcutStyle",
        default: .focusOnRelease,
        gate: PreferenceGate(
            freeEquivalent: .doNothingOnRelease,
            rememberedKey: "rememberedShortcutStyle",
            isProValue: { $0 == .searchOnRelease }))

    // Per-shortcut overrides for shortcut 0 (the only index reachable while Pro is locked, since
    // extra shortcuts >= 1 are hard-gated at trigger time). Snapshot/restore plumbing mirrors the
    // global gates above. Registered defaults are the FREE values, so `snapshotAndDowngrade` is a
    // no-op for unset overrides — only explicitly-set Pro overrides get snapshotted on lock.
    static let appearanceStyleOverride0 = PreferenceDefinition<AppearanceStylePreference>(
        key: "appearanceStyleOverride",
        default: .thumbnails,
        gate: PreferenceGate(
            freeEquivalent: .thumbnails,
            rememberedKey: "rememberedAppearanceStyleOverride",
            isProValue: { $0 != .thumbnails }))

    static let appearanceSizeOverride0 = PreferenceDefinition<AppearanceSizePreference>(
        key: "appearanceSizeOverride",
        default: .medium,
        gate: PreferenceGate(
            freeEquivalent: .medium,
            rememberedKey: "rememberedAppearanceSizeOverride",
            isProValue: { $0 == .auto }))

    static let shortcutStyleOverride0 = PreferenceDefinition<ShortcutStylePreference>(
        key: "shortcutStyleOverride",
        default: .doNothingOnRelease,
        gate: PreferenceGate(
            freeEquivalent: .doNothingOnRelease,
            rememberedKey: "rememberedShortcutStyleOverride",
            isProValue: { $0 == .searchOnRelease }))

    /// All Pro-gated preferences as type-erased descriptors. Iterated by `ProTransitionState`
    /// on lock / unlock.
    static let all: [AnyProGatedPreference] = [
        appearanceStyle.erased,
        appearanceSize.erased,
        shortcutStyle.erased,
        appearanceStyleOverride0.erased,
        appearanceSizeOverride0.erased,
        shortcutStyleOverride0.erased,
    ]

    /// Lookup by storage key. nil for non-gated preferences.
    static func forPreferenceKey(_ key: String) -> AnyProGatedPreference? {
        return all.first { $0.preferenceKey == key }
    }
}
