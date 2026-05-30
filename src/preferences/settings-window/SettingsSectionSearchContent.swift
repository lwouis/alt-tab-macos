import Cocoa

/// A Settings section's searchable content, split into a fixed **base** captured during the
/// section's build-time `SettingsSearchIndex.indexed { }` scope and a replaceable **dynamic** part
/// for content that is rebuilt while the section is already live.
///
/// Why the split exists: most controls are built once, so the push-based index harvested at build
/// time stays valid for the session. But ControlsTab's shortcut sidebar rows ("Shortcut 1",
/// "Shortcut 2", …) are torn down and recreated by `refreshShortcutRows` — which runs *outside* the
/// build scope (via `preferenceChanged`, the +/- buttons, input-source changes, the pro-lock
/// observer, …). Their inline `registerSearchContent` no-ops there (no active builder), and the
/// section's base targets keep pointing at the now-removed labels, so a query like "sho" stopped
/// lighting up the rebuilt rows. Sections that manage such rows skip them in the build-time walk
/// (so they never land in `base`) and re-publish them here via `setDynamic` after every rebuild —
/// a wholesale swap that leaves no stale targets behind and makes freshly-added rows searchable.
final class SettingsSectionSearchContent {
    private let baseStrings: [String]
    private let baseTargets: [SettingsSearchHighlightTarget]
    private var dynamicStrings: [String] = []
    private var dynamicTargets: [SettingsSearchHighlightTarget] = []

    init(strings: [String] = [], targets: [SettingsSearchHighlightTarget] = []) {
        baseStrings = strings
        baseTargets = targets
    }

    /// Replace the dynamic part wholesale. Called after a section rebuilds its sidebar rows, with
    /// the strings + highlight targets freshly registered from the *current* rows. Replacing (not
    /// appending) is the whole point: targets for removed rows are dropped, so no stale highlight
    /// targets accumulate and `searchableStrings` never reports rows that no longer exist.
    func setDynamic(strings: [String], targets: [SettingsSearchHighlightTarget]) {
        dynamicStrings = strings
        dynamicTargets = targets
    }

    var searchableStrings: [String] { baseStrings + dynamicStrings }
    var highlightTargets: [SettingsSearchHighlightTarget] { baseTargets + dynamicTargets }

    /// True when the query is empty (everything matches) or any base/dynamic string or highlight
    /// target matches it. Drives whether the section stays visible in filtered search results.
    func matches(_ query: String) -> Bool {
        if SettingsSearch.isQueryEmpty(query) { return true }
        if searchableStrings.contains(where: { SettingsSearch.match(query, in: $0) != nil }) { return true }
        return highlightTargets.contains { $0.hasMatch(query) }
    }

    func highlightMatches(_ query: String) {
        highlightTargets.forEach { $0.updateHighlight(query) }
    }

    func clearHighlights() {
        highlightTargets.forEach { $0.clear() }
    }
}
