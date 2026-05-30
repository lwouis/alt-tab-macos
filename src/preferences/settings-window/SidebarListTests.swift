import XCTest
import Cocoa

/// Coverage for `SidebarListRow`'s Pro-badge management.
///
/// Why this suite exists: the shortcut sidebar rows are recycled across refreshes (ControlsTab's
/// `refreshShortcutRows`), so `setProBadge` is called repeatedly on the *same* row instead of once
/// on a fresh one. The original implementation removed the badge from its wrapper but left the
/// now-empty wrapper in the title row, then appended a new wrapper — so the wrappers piled up, each
/// adding the title row's spacing, progressively squeezing and head-truncating "Shortcut 2" /
/// "Shortcut 3". These tests pin that `setProBadge` is idempotent and fully removes its wrapper.
///
/// (`SidebarListRow` compiles into the test target: the deployment target is 10.13 — same as the
/// app — and `_test-support/Mocks.swift` stubs the few app-only symbols it touches,
/// `SettingsWindow.contentWidth` and `SettingsSearchIndex`.)
final class SidebarListTests: XCTestCase {

    private func descendantViews(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendantViews($0) }
    }

    private func badgeCount(_ row: NSView) -> Int {
        descendantViews(row).filter { $0 is ProBadgeView }.count
    }

    func testSetProBadgeDoesNotAccumulateWrappers() {
        let row = SidebarListRow()
        row.setContent("Shortcut 2", "")
        row.setProBadge(true)
        let viewCountWithBadge = descendantViews(row).count
        row.setProBadge(true)
        row.setProBadge(true)
        XCTAssertEqual(descendantViews(row).count, viewCountWithBadge,
            "regression: repeated setProBadge(true) on a recycled row must not add views — leftover empty badge wrappers piling up in the title row is what progressively truncated 'Shortcut N'")
        XCTAssertEqual(badgeCount(row), 1,
            "exactly one badge must remain after repeated setProBadge(true)")
    }

    func testSetProBadgeAddsThenFullyRemovesBadge() {
        let row = SidebarListRow()
        row.setContent("Shortcut 2", "")
        let baselineViewCount = descendantViews(row).count
        row.setProBadge(true)
        XCTAssertEqual(badgeCount(row), 1, "setProBadge(true) adds the badge")
        row.setProBadge(false)
        XCTAssertEqual(badgeCount(row), 0, "setProBadge(false) removes the badge")
        XCTAssertEqual(descendantViews(row).count, baselineViewCount,
            "regression: setProBadge(false) must remove the whole wrapper (not leave an empty one behind), returning to the no-badge view count")
    }
}
