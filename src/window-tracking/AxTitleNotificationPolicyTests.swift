import XCTest

/// Pins `AxTitleNotificationPolicy.verdict` — the decision extracted from `AxObserverRegistry.refreshTitle`.
/// Pure data in, a verdict out: no AX, no IPC, no globals.
///
/// The #6011 regression: an `AXTitleChanged` naming a node INSIDE a Chromium window was recorded as that
/// window's title. The node's title is empty, an empty title falls back to the app name when the
/// WindowServer has none either, and the switcher listed a live browser window as "Chromium".
class AxTitleNotificationPolicyTests: XCTestCase {

    // MARK: - A. The window's own rename

    /// an `AXWindow` naming a title records that title
    func testWindowTitleIsApplied() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: kAXWindowRole, title: "Medical Spa - Chromium"),
            .apply("Medical Spa - Chromium"))
    }

    /// an empty title from the window itself is applied as empty: the window really has no title, and
    /// choosing what to show for that belongs to `Window.bestEffortTitle`
    func testEmptyWindowTitleIsApplied() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: kAXWindowRole, title: ""), .apply(""))
    }

    // MARK: - B. Deliveries that say nothing about the window's title

    /// the window element answered no `kAXTitle` at all, which is not an answer about the title
    func testMissingTitleIsIgnored() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: kAXWindowRole, title: nil), .ignoreNoTitle)
    }

    /// the #6011 shape: a static text inside the window, its own title empty, its wid the window's
    func testEmptyDescendantTitleIsIgnored() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: kAXStaticTextRole, title: ""),
            .ignoreNotTheWindow)
    }

    /// the role decides before the string: a descendant carrying a perfectly good title is still not the
    /// window, and a plausible string from the wrong element is the harder bug to see
    func testDescendantWithATitleIsIgnored() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: kAXStaticTextRole, title: "Today's Specials"),
            .ignoreNotTheWindow)
    }

    /// the same for the `AXGroup` shape Slack and Electron shells present
    func testGroupDescendantIsIgnored() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: kAXGroupRole, title: "Threads"),
            .ignoreNotTheWindow)
    }

    /// an element that would not say what it is proves nothing, so it is refused
    func testUnknownRoleIsIgnored() {
        XCTAssertEqual(AxTitleNotificationPolicy.verdict(role: nil, title: "Untitled"), .ignoreNotTheWindow)
    }
}
