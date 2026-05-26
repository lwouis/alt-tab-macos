import Cocoa

/// Search index for the Settings UI.
///
/// Two responsibilities:
///
/// 1. **Inline registration during section construction.** Before Phase 3 the index was built by
///    `SettingsWindow.collectSearchContent`, a post-construction recursive walk that visited every
///    NSView in a section's tree and shape-matched its strings out of it (two traversals per
///    section: construct, then harvest). The new model is push, not pull: as each widget factory
///    (`LabelAndControl.makeDropdown`, `TableGroupView.makeText`, etc.) builds a control, it
///    pushes the strings it would produce — plus a `SettingsSearchHighlightTarget` (a closure-bag
///    that knows how to highlight that specific control) — into the currently-active `Builder`.
///    `SettingsWindow.addSection` opens a builder before calling the section's view-builder
///    closure and closes it after; the resulting `Builder.strings` and `Builder.targets` are
///    exactly what the old walk produced, just collected during construction rather than after.
///    A post-construction walk still runs as a safety net for any direct widget creation that
///    bypasses the factories.
///
/// 2. **Pre-build sheet metadata.** Sheets are lazy (Phase 2) — their view trees don't exist
///    until the user opens them once. Search's button-match check needs to know whether a sheet's
///    content matches the query *before* the sheet has ever been built, so each sheet class
///    declares its own `static let searchableStrings: [String]` and the lookup below maps the
///    button's action selector to that static list. Once the sheet is built, the live-view walk
///    in `SettingsWindow.highlightTarget(_ button:)` adds on top for in-sheet highlighting.
enum SettingsSearchIndex {

    // MARK: - Inline registration

    /// The currently-active builder, or nil outside of `indexed(_:)`. Factories check this and
    /// silently no-op when nil so they can be called from any context.
    static var current: Builder?

    final class Builder {
        var strings: [String] = []
        var targets: [SettingsSearchHighlightTarget] = []
    }

    /// Run `build` with a fresh builder active, then return the built value alongside the
    /// accumulated index. Nested `indexed` calls restore the previous builder on exit.
    static func indexed<T>(_ build: () -> T) -> (result: T, builder: Builder) {
        let previous = current
        let builder = Builder()
        current = builder
        defer { current = previous }
        let result = build()
        return (result, builder)
    }

    /// Push a string. No-op if the string is empty/whitespace-only or no builder is active.
    static func registerString(_ s: String?) {
        guard let current, let s else { return }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { current.strings.append(trimmed) }
    }

    /// Push multiple strings — convenience for popups, segmented controls, info-button tooltips.
    static func registerStrings(_ strings: [String]) {
        guard let current else { return }
        for s in strings {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { current.strings.append(t) }
        }
    }

    /// Push a highlight target. No-op if nil (factories may pass nil for non-highlightable cases).
    static func registerTarget(_ target: SettingsSearchHighlightTarget?) {
        guard let target, let current else { return }
        current.targets.append(target)
    }

    // MARK: - Pre-build sheet metadata

    /// Look up static searchable strings for a sheet by its opener-button action selector. Used
    /// by `SettingsWindow.highlightTarget(_ button:)` to match a query against an unbuilt sheet's
    /// contents. Each sheet class declares its own `static let searchableStrings: [String]` — keep
    /// those in sync with the sheet's `makeContentView` by convention.
    static func sheetSearchableStrings(forButtonAction action: Selector) -> [String]? {
        if action == #selector(AppearanceTab.showCustomizeStyleSheet) { return CustomizeStyleSheet.searchableStrings }
        if action == #selector(AppearanceTab.showAnimationsSheet) { return AnimationsSheet.searchableStrings }
        if action == #selector(ControlsTab.showShortcutsSettings) { return ShortcutsWhenActiveSheet.searchableStrings }
        if action == #selector(ControlsTab.showAdditionalControlsSettings) { return AdditionalControlsSheet.searchableStrings }
        return nil
    }
}
