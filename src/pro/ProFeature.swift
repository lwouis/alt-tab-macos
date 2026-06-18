import Foundation

/// Registry of every Pro-gated capability. Single source of truth for:
/// - which preferences degrade when Pro locks (and how to snapshot / restore them)
/// - which runtime actions are hard-gated
/// - which preference keys the click-interceptor routes to the Upgrade tab
/// - which copy the Day X views use when showing the feature in context
enum ProFeature: Equatable, Hashable {
    // Degradable preferences. Stored value is snapshotted into `remembered*` on lock and restored on unlock.
    case appIconsAndTitlesStyle
    case autoSize
    case searchOnReleaseShortcut
    // Hard-gated runtime actions. No stored preference; gated at use-time.
    case extraShortcut(index: Int)
    case searchInSwitcher

    enum GateKind {
        /// Silent fallback only. Stored value is downgraded on lock; no [C] from this alone.
        case degradable
        /// Use-time free-pass → [C] ladder. No stored preference.
        case hardGated
        /// Both: silent downgrade AND first post-expiration switcher summon triggers [C].
        case degradableAndHardGated
    }

    var gateKind: GateKind {
        switch self {
        case .autoSize: return .degradable
        case .appIconsAndTitlesStyle, .searchOnReleaseShortcut: return .degradableAndHardGated
        case .extraShortcut, .searchInSwitcher: return .hardGated
        }
    }

    /// The Pro-gated preference backing this feature, if any. Non-nil only for degradable features.
    /// Source of truth for key, remembered-key, read/downgrade/restore — see `ProGatedPreferences`.
    var gatedPreference: AnyProGatedPreference? {
        switch self {
        case .appIconsAndTitlesStyle: return ProGatedPreferences.appearanceStyle.erased
        case .autoSize: return ProGatedPreferences.appearanceSize.erased
        case .searchOnReleaseShortcut: return ProGatedPreferences.shortcutStyle.erased
        case .extraShortcut, .searchInSwitcher: return nil
        }
    }

    /// The marketing copy used in feature lists (Day 1 table, Day 15 Full Upgrade, UpgradeTab, etc.).
    /// Multiple cases can share the same marketing line (e.g. extraShortcut + searchOnReleaseShortcut
    /// both map to "keyboard shortcuts").
    var copy: String {
        switch self {
        case .appIconsAndTitlesStyle: return ProFeatureCopy.appIconsAndTitles
        case .autoSize: return ProFeatureCopy.autoSize
        case .searchOnReleaseShortcut: return ProFeatureCopy.extraShortcuts // grouped under "keyboard shortcuts"
        case .extraShortcut: return ProFeatureCopy.extraShortcuts
        case .searchInSwitcher: return ProFeatureCopy.search
        }
    }

    /// Features whose stored preference is snapshotted + downgraded when Pro locks.
    static let degradable: [ProFeature] = [.appIconsAndTitlesStyle, .autoSize, .searchOnReleaseShortcut]

    /// True when the user has Pro available (pro or trial). Centralised so future variants
    /// (grace periods, per-feature flags) have one place to change.
    var isAvailable: Bool { LicenseManager.shared.isProAvailable }
    /// True when Pro is locked (post-expiration).
    var isLocked: Bool { LicenseManager.shared.isProLocked }

    /// Attempt to use this feature at runtime. Returns `true` if the action should proceed.
    /// For hard-gated features during trial/pro the answer is always `true`; once locked this
    /// consults the free-pass ladder in `ProTransitionManager`. Degradable-only features
    /// always return `true` because they are gated at preference-write time, not at use time.
    /// During an active free-pass session every feature is allowed without re-consuming the
    /// free pass — the user is mid-session with one Pro summon, so search and extra-shortcut
    /// chords inside that session must work without firing [C] inline.
    func attemptUse() -> Bool {
        if LicenseManager.shared.isProAvailable { return true }
        if ProTransitionManager.shared.isFreePassSessionActive { return true }
        switch self {
        case .extraShortcut, .searchInSwitcher:
            return ProTransitionManager.shared.attemptHardGatedFeature(self)
        case .appIconsAndTitlesStyle, .autoSize, .searchOnReleaseShortcut:
            return true
        }
    }

    /// True when the user's stored preference currently holds the Pro value. Used by
    /// `PreferencesEvents.preferenceChanged` to decide whether a setter should bounce to Upgrade.
    static func isStoredValuePro(preferenceKey: String) -> Bool {
        ProGatedPreferences.forPreferenceKey(preferenceKey)?.isStoredValuePro() ?? false
    }
}
