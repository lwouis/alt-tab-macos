import Foundation

/// All per-shortcut preferences bundled into one value, replacing the 9 parallel arrays that
/// used to be indexed separately (`Preferences.appsToShow[i]`, `Preferences.spacesToShow[i]`, …).
/// Persistence is unchanged — the indexed keys (`appsToShow`, `appsToShow2`, …) still back each
/// field via `indexToName(_:_:)`. Call sites that used to index 9 arrays can now read one
/// configuration: `Preferences.shortcut(at: shortcutIndex).appsToShow`.
struct ShortcutConfiguration {
    let appsToShow: AppsToShowPreference
    let spacesToShow: SpacesToShowPreference
    let screensToShow: ScreensToShowPreference
    let showMinimizedWindows: ShowHowPreference
    let showHiddenWindows: ShowHowPreference
    let showFullscreenWindows: ShowHowPreference
    let showWindowlessApps: ShowHowPreference
    let windowOrder: WindowOrderPreference
    let shortcutStyle: ShortcutStylePreference
}

extension Preferences {
    /// Read the configuration for a single shortcut index. Persistence format is unchanged —
    /// each field still reads from its indexed key via `CachedUserDefaults.macroPref`.
    static func shortcut(at index: Int) -> ShortcutConfiguration {
        ShortcutConfiguration(
            appsToShow: CachedUserDefaults.macroPref(indexToName("appsToShow", index), AppsToShowPreference.allCases),
            spacesToShow: CachedUserDefaults.macroPref(indexToName("spacesToShow", index), SpacesToShowPreference.allCases),
            screensToShow: CachedUserDefaults.macroPref(indexToName("screensToShow", index), ScreensToShowPreference.allCases),
            showMinimizedWindows: CachedUserDefaults.macroPref(indexToName("showMinimizedWindows", index), ShowHowPreference.allCases),
            showHiddenWindows: CachedUserDefaults.macroPref(indexToName("showHiddenWindows", index), ShowHowPreference.allCases),
            showFullscreenWindows: CachedUserDefaults.macroPref(indexToName("showFullscreenWindows", index), ShowHowPreference.allCases),
            showWindowlessApps: CachedUserDefaults.macroPref(indexToName("showWindowlessApps", index), ShowHowPreference.allCases),
            windowOrder: CachedUserDefaults.macroPref(indexToName("windowOrder", index), WindowOrderPreference.allCases),
            shortcutStyle: CachedUserDefaults.macroPref(indexToName("shortcutStyle", index), ShortcutStylePreference.allCases)
        )
    }
}
