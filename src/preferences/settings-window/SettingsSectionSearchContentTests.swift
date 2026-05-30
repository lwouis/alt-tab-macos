import XCTest
import Cocoa

/// Coverage for `SettingsSectionSearchContent` — the per-section search store that splits a fixed
/// build-time "base" from a replaceable "dynamic" part.
///
/// Why this suite exists: typing "sho" stopped highlighting ControlsTab's "Shortcut 1"/"Shortcut 2"
/// sidebar rows after they were rebuilt (the +/- buttons, a recorder edit, an input-source change,
/// the pro-lock observer). The rows are recreated *outside* the section's build-time `indexed { }`
/// scope, so their inline registration no-ops and the section's cached targets keep pointing at the
/// removed labels. The fix routes such rows through the dynamic part and re-publishes them wholesale
/// on every rebuild. These tests pin that the dynamic part is searchable, that re-publishing
/// *replaces* (never accumulates, never leaves a stale target), and that highlighting drives it.
///
/// We exercise the section store with plain `NSTextField` targets — exactly what the rows feed it,
/// and the cleanest unit. (`ControlsTab` itself can't compile into the test target — its trigger
/// row + sheets drag in the whole settings window — so the live re-publish path is verified by
/// running the app, not here.)
final class SettingsSectionSearchContentTests: XCTestCase {

    private func target(_ title: String) -> SettingsSearchHighlightTarget {
        SettingsSearchHighlight.highlightTarget(NSTextField(labelWithString: title))!
    }

    private func hasMatchColor(_ textField: NSTextField) -> Bool {
        let attr = textField.attributedStringValue
        var found = false
        attr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if value as? NSColor == Appearance.searchMatchForegroundColor { found = true }
        }
        return found
    }

    func testEmptyQueryAlwaysMatches() {
        let content = SettingsSectionSearchContent()
        XCTAssertTrue(content.matches(""), "an empty query keeps every section visible")
        XCTAssertTrue(content.matches("   "), "a whitespace-only query is treated as empty")
    }

    func testBaseStringIsSearchable() {
        let content = SettingsSectionSearchContent(strings: ["Appearance"], targets: [])
        XCTAssertTrue(content.matches("appea"), "a base string must drive a match")
        XCTAssertFalse(content.matches("zzzzz"), "a non-matching query must not match")
    }

    func testDynamicStringIsSearchable() {
        let content = SettingsSectionSearchContent()
        content.setDynamic(strings: ["Shortcut 1"], targets: [])
        XCTAssertTrue(content.matches("sho"),
            "a string published via setDynamic must be searchable — this is the sidebar-row path")
    }

    func testDynamicTargetReportsAndHighlightsMatch() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        let content = SettingsSectionSearchContent()
        content.setDynamic(strings: [], targets: [SettingsSearchHighlight.highlightTarget(tf)!])
        XCTAssertTrue(content.matches("Sho"), "a dynamic highlight target alone must drive section visibility")
        content.highlightMatches("Sho")
        XCTAssertTrue(hasMatchColor(tf), "highlightMatches must light up the dynamic target's label")
    }

    /// The exact regression: rebuilt "Shortcut N" rows must light up again. Publishing the recreated
    /// rows replaces the dynamic part — the previous rows' targets are dropped (no stale highlight),
    /// the previous rows stop being searchable, and the new rows match + highlight.
    func testSetDynamicReplacesAndDropsStaleTargets() {
        let content = SettingsSectionSearchContent()
        let firstTf = NSTextField(labelWithString: "Shortcut 1")
        let firstTarget = SettingsSearchHighlight.highlightTarget(firstTf)!
        content.setDynamic(strings: ["Shortcut 1"], targets: [firstTarget])
        XCTAssertTrue(content.matches("Shortcut 1"))

        // Rebuild: refreshShortcutRows recreates the rows as fresh instances.
        let rebuiltTf = NSTextField(labelWithString: "Shortcut 2")
        let rebuiltTarget = SettingsSearchHighlight.highlightTarget(rebuiltTf)!
        content.setDynamic(strings: ["Shortcut 2"], targets: [rebuiltTarget])

        XCTAssertFalse(content.highlightTargets.contains { $0 === firstTarget },
            "the removed row's highlight target must be dropped, not left dangling")
        XCTAssertTrue(content.highlightTargets.contains { $0 === rebuiltTarget },
            "the rebuilt row's highlight target must be registered")
        XCTAssertFalse(content.matches("Shortcut 1"),
            "the removed row must no longer be searchable")
        XCTAssertTrue(content.matches("Shortcut 2"),
            "the rebuilt row must be searchable")
        content.highlightMatches("Sho")
        XCTAssertTrue(hasMatchColor(rebuiltTf),
            "regression: a rebuilt 'Shortcut N' row must light up when the user types 'sho'")
    }

    func testSetDynamicReplaceDoesNotAccumulate() {
        let content = SettingsSectionSearchContent(strings: ["Base"], targets: [])
        content.setDynamic(strings: ["Alpha"], targets: [target("Alpha")])
        let second = target("Bravo")
        content.setDynamic(strings: ["Bravo"], targets: [second])
        XCTAssertEqual(content.highlightTargets.count, 1,
            "replacing dynamic content must not accumulate targets across rebuilds")
        XCTAssertTrue(content.highlightTargets.contains { $0 === second })
        XCTAssertEqual(content.searchableStrings, ["Base", "Bravo"],
            "searchableStrings is base + the latest dynamic strings only")
    }

    func testClearHighlightsClearsDynamicTargets() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        let content = SettingsSectionSearchContent()
        content.setDynamic(strings: [], targets: [SettingsSearchHighlight.highlightTarget(tf)!])
        content.highlightMatches("Sho")
        XCTAssertTrue(hasMatchColor(tf))
        content.clearHighlights()
        XCTAssertFalse(hasMatchColor(tf), "clearHighlights must revert dynamic targets too")
    }
}
