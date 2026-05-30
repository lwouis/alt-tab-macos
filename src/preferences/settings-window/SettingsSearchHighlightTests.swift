import XCTest
import Cocoa

/// Coverage for the settings-search *highlight* machinery — the layer that turns a query match
/// into yellow-highlighted text on a specific control.
///
/// Why this suite exists: we've repeatedly regressed search highlighting in the editor. The most
/// recent case was the sidebar shortcut rows ("Shortcut 1", "Shortcut 2", …) no longer lighting
/// up when the user typed "sho". Two distinct things have to work for that to happen:
///
///   1. `SettingsSearchHighlight.highlightTarget(_:)` must turn a label into a *working*
///      `SettingsSearchHighlightTarget` — one that reports a match and applies the highlight to
///      the matched range. (Tier A: the factory + target in isolation.)
///   2. The widget factories (`TableGroupView.makeText`, and `SidebarListRow.registerSearchContent`
///      for the sidebar) must *register* that target into the active `SettingsSearchIndex.Builder`,
///      so a section's search actually drives it. (Tier B: factory ⇄ index wiring.)
///
/// The sidebar rows feed `NSTextField` labels into `highlightTarget`; the rounded-section rows
/// feed `LightLabel`. Both overloads are covered. (`SidebarListRow` itself — and its Pro-badge
/// recycling — is covered separately in `SidebarListTests`; it compiles into this target fine.)
final class SettingsSearchHighlightTests: XCTestCase {

    // MARK: - Tier A: NSTextField highlight target (what sidebar rows use)

    func testTextFieldTargetReportsMatch() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        guard let target = SettingsSearchHighlight.highlightTarget(tf) else {
            return XCTFail("a non-empty label must produce a highlight target — sidebar rows rely on this to be searchable")
        }
        XCTAssertTrue(target.hasMatch("Sho"),
            "regression: a prefix query must match the label text — this is exactly the 'typing sho doesn't highlight Shortcut N' bug")
        XCTAssertFalse(target.hasMatch("zzz"),
            "a non-matching query must not report a match")
    }

    func testTextFieldTargetIsNilForEmptyLabel() {
        let tf = NSTextField(labelWithString: "")
        XCTAssertNil(SettingsSearchHighlight.highlightTarget(tf),
            "an empty label has nothing to highlight, so the factory returns nil (the index skips it)")
    }

    func testTextFieldHighlightAppliesSearchColorToMatchedRange() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        let target = SettingsSearchHighlight.highlightTarget(tf)!
        target.updateHighlight("Sho")
        // The matched prefix [0..<3] must carry the search-match foreground color; the rest of the
        // string must NOT (it falls through to the textField's own textColor — that's what keeps
        // selection-driven color changes working, per the highlightTarget contract).
        let attr = tf.attributedStringValue
        XCTAssertEqual(attr.string, "Shortcut 1")
        var matchedRangeHasColor = false
        var tailHasColor = false
        attr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            guard value as? NSColor == Appearance.searchMatchForegroundColor else { return }
            if range.location == 0, range.length == 3 { matchedRangeHasColor = true }
            if range.location >= 3 { tailHasColor = true }
        }
        XCTAssertTrue(matchedRangeHasColor,
            "regression: the matched prefix must be tinted with the search-match color")
        XCTAssertFalse(tailHasColor,
            "regression: only the matched range may be tinted — tinting the whole string is the bug that froze the boldness/color on the wrong selection")
    }

    func testTextFieldHighlightClearsBackToPlain() {
        let tf = NSTextField(labelWithString: "Shortcut 1")
        let target = SettingsSearchHighlight.highlightTarget(tf)!
        target.updateHighlight("Sho")   // apply
        target.updateHighlight("zzz")   // no match → clears
        let attr = tf.attributedStringValue
        var anyColor = false
        attr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if value as? NSColor == Appearance.searchMatchForegroundColor { anyColor = true }
        }
        XCTAssertFalse(anyColor,
            "after a non-matching query the highlight must be fully cleared so no stale yellow text remains")
    }

    // MARK: - Tier A: LightLabel highlight target (what rounded-section rows use)

    func testLightLabelTargetAppliesAndClearsRanges() {
        let label = LightLabel("Group apps")
        guard let target = SettingsSearchHighlight.highlightTarget(label) else {
            return XCTFail("a non-empty LightLabel must produce a highlight target")
        }
        XCTAssertTrue(target.hasMatch("Group"))
        target.updateHighlight("Group")
        XCTAssertEqual(label.highlightRanges, [NSRange(location: 0, length: 5)],
            "regression: LightLabel must receive the matched range so it can draw the yellow background inline on its next draw")
        target.updateHighlight("zzz")
        XCTAssertTrue(label.highlightRanges.isEmpty,
            "a non-matching query must clear the LightLabel's highlight ranges")
    }

    // MARK: - Tier B: factory ⇄ index registration wiring

    /// `TableGroupView.makeText` is the row-title factory for every rounded settings section. It
    /// must, as a side effect of construction, push its string + a highlight target into whatever
    /// `SettingsSearchIndex.Builder` is active. This is the same inline-registration contract that
    /// `SidebarListRow.registerSearchContent` relies on — and whose absence was the sidebar
    /// search regression. If `makeText` ever stops registering, this fails.
    func testMakeTextRegistersStringAndTargetInActiveBuilder() {
        let (label, builder) = SettingsSearchIndex.indexed {
            TableGroupView.makeText("Order windows by")
        }
        XCTAssertEqual(label.stringValue, "Order windows by")
        XCTAssertTrue(builder.strings.contains("Order windows by"),
            "regression: makeText must register its label string into the active search index")
        XCTAssertEqual(builder.targets.count, 1,
            "regression: makeText must register exactly one highlight target — without it the label is searchable-by-string but never lights up")
        XCTAssertTrue(builder.targets.first?.hasMatch("Order") ?? false,
            "the registered target must actually match the label's text")
    }

    /// The index is push-based and scoped: factories called with no active builder must silently
    /// no-op (so they're safe to call from any context, e.g. a `refreshShortcutRows` that runs
    /// outside the section-build scope). Pins that contract.
    func testMakeTextOutsideIndexedScopeDoesNotCrashOrLeak() {
        SettingsSearchIndex.current = nil
        let label = TableGroupView.makeText("Theme")
        XCTAssertEqual(label.stringValue, "Theme",
            "makeText must still build the label when no builder is active; registration just no-ops")
    }
}
