import Foundation

/// Every Pro-gated capability, and the two questions the rest of the app asks about them: may this
/// action proceed right now (`attemptUse`), and does this preference key currently hold a Pro value
/// (`isStoredValuePro`). The gating data itself lives in `ProGatedPreferences`.
enum ProFeature: Equatable, Hashable {
    // Degradable preferences. Stored value is snapshotted into `remembered*` on lock and restored on unlock.
    case appIconsAndTitlesStyle
    case autoSize
    case searchOnReleaseShortcut
    // Hard-gated runtime actions. No stored preference; gated at use-time.
    case extraShortcut(index: Int)
    case searchInSwitcher

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
