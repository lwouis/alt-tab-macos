import XCTest

/// Pins `BruteForceWindowMatch.isTargetWindowRoot` — the decision extracted from
/// `AXUIElement.windowsByBruteForce`. Pure data in, `Bool` out: no AX, no IPC, no globals.
///
/// The #5849 regression: `_AXUIElementGetWindow` returns the containing window's id for a window's
/// DESCENDANTS too, so a brute-force scan that stopped at the first wid match returned a descendant
/// (`AXOutline` / `AXMenuButton` / `AXGroup`) instead of the `AXWindow` root, and admission
/// dropped the window entirely. These tests guarantee only the `AXWindow` root for the target wid is
/// accepted, so a descendant sharing the wid can never win the scan again.
final class BruteForceWindowMatchTests: XCTestCase {

    private static let targetWid: CGWindowID = 42637 // hodeinavarro's failing Finder window
    private static let otherWid: CGWindowID = 99999

    // MARK: - A. The root window element is accepted

    func testAcceptsAxWindowRootForTargetWid() {
        XCTAssertTrue(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: Self.targetWid, candidateRole: kAXWindowRole, targetWid: Self.targetWid))
    }

    // MARK: - B. Descendants sharing the wid are skipped (the #5849 regression guard)

    func testSkipsAxOutlineDescendant() {
        // Finder: element 697 (AXOutline) precedes element 698 (AXWindow), both owning wid 42637.
        XCTAssertFalse(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: Self.targetWid, candidateRole: kAXOutlineRole, targetWid: Self.targetWid))
    }

    func testSkipsAxMenuButtonDescendant() {
        // Telegram: the "Main menu" AXMenuButton resolved to the Telegram window's wid.
        XCTAssertFalse(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: Self.targetWid, candidateRole: kAXMenuButtonRole, targetWid: Self.targetWid))
    }

    func testSkipsAxGroupDescendant() {
        // Slack: the window transiently presents an AXGroup child owning its wid.
        XCTAssertFalse(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: Self.targetWid, candidateRole: kAXGroupRole, targetWid: Self.targetWid))
    }

    func testSkipsNilRoleDescendant() {
        XCTAssertFalse(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: Self.targetWid, candidateRole: nil, targetWid: Self.targetWid))
    }

    // MARK: - C. A window element belonging to a DIFFERENT wid is not the target

    func testRejectsAxWindowOfOtherWid() {
        XCTAssertFalse(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: Self.otherWid, candidateRole: kAXWindowRole, targetWid: Self.targetWid))
    }

    func testRejectsNilWid() {
        XCTAssertFalse(BruteForceWindowMatch.isTargetWindowRoot(
            candidateWid: nil, candidateRole: kAXWindowRole, targetWid: Self.targetWid))
    }

    // MARK: - D. Scan-order invariant (descendant before root)

    func testScanSelectsRootNotEarlierDescendant() {
        // hodeinavarro's exact rows: the AXOutline sits BEFORE the AXWindow in scan order.
        let candidates: [(wid: CGWindowID?, role: String?)] = [
            (Self.targetWid, kAXOutlineRole), // element 697
            (Self.targetWid, kAXWindowRole),  // element 698 (the real window)
        ]
        let picked = candidates.firstIndex {
            BruteForceWindowMatch.isTargetWindowRoot(candidateWid: $0.wid, candidateRole: $0.role, targetWid: Self.targetWid)
        }
        XCTAssertEqual(picked, 1, "the scan must skip the earlier AXOutline and select the AXWindow root")
    }

    // MARK: - E. One traversal can collect several target roots

    func testBatchCollectsEveryRequestedRootWithoutAcceptingDescendants() {
        let requested: Set<CGWindowID> = [Self.targetWid, Self.otherWid]
        let candidates: [(wid: CGWindowID?, role: String?)] = [
            (Self.targetWid, kAXOutlineRole),
            (Self.targetWid, kAXWindowRole),
            (777, kAXWindowRole),
            (Self.otherWid, kAXGroupRole),
            (Self.otherWid, kAXWindowRole),
        ]
        var remaining = requested
        for candidate in candidates {
            guard let wid = candidate.wid, remaining.contains(wid),
                  BruteForceWindowMatch.isTargetWindowRoot(
                    candidateWid: wid, candidateRole: candidate.role, targetWid: wid) else { continue }
            remaining.remove(wid)
        }
        XCTAssertTrue(remaining.isEmpty, "one traversal must collect both roots and ignore their earlier descendants")
    }

    // MARK: - F. Whose tab is it? (the 2026-08-01 cross-window adoption)

    /// The two Finder windows of the capture: parked 520pt apart, every tab titled "lwouis".
    private static let requester = CGRect(x: 80, y: 80, width: 1000, height: 440)
    private static let otherWindow = CGRect(x: 80, y: 600, width: 1000, height: 440)

    func testAdoptsATabParkedOnTheRequester() {
        XCTAssertTrue(BruteForceWindowMatch.isPlausibleInactiveTab(
            candidate: Self.requester, requester: Self.requester, otherWindowsOfApp: [Self.otherWindow]))
    }

    /// The captured failure: the scan run for the window at y=80 found a candidate sitting exactly on the
    /// window at y=600. That is the OTHER window's inactive tab — adopting it put a member of window B into
    /// window A's group, and when the user switched to that tab it became A's representative, so every real
    /// member of A stopped being drawn and A vanished from the switcher.
    func testRejectsATabParkedOnAnotherWindowOfTheSameApp() {
        XCTAssertFalse(BruteForceWindowMatch.isPlausibleInactiveTab(
            candidate: Self.otherWindow, requester: Self.requester, otherWindowsOfApp: [Self.otherWindow]))
    }

    /// Merge All Windows never converges the absorbed windows' frames: they keep their own cascade positions,
    /// frozen, one 29px step apart from each other and from the merged window. Demanding a match with the
    /// requester would make those tabs permanently un-adoptable, so a frame that sits on NOTHING
    /// is waved through.
    func testAdoptsAMergedTabAtItsOwnFrozenCascadePosition() {
        let merged = CGRect(x: 942, y: 277, width: 757, height: 543)
        let absorbed = CGRect(x: 913, y: 248, width: 757, height: 543)
        XCTAssertTrue(BruteForceWindowMatch.isPlausibleInactiveTab(
            candidate: absorbed, requester: merged, otherWindowsOfApp: []))
    }

    /// A tab whose size has drifted from its parent's (the tab bar resizes members) is still ours: the test is
    /// on position alone, the same fact `TabGroupResolver.framePartitions` keys on.
    func testAdoptsATabWhoseSizeDriftedFromItsParent() {
        let drifted = CGRect(x: 80, y: 80, width: 1000, height: 412)
        XCTAssertTrue(BruteForceWindowMatch.isPlausibleInactiveTab(
            candidate: drifted, requester: Self.requester, otherWindowsOfApp: [Self.otherWindow]))
    }

    /// Nothing known about the requester's frame (not tracked, or no geometry yet) — the gate has no evidence
    /// to reject on, and a missed adoption costs a retry while a wrong one hides a window.
    func testAdoptsWhenTheRequestersFrameIsUnknown() {
        XCTAssertTrue(BruteForceWindowMatch.isPlausibleInactiveTab(
            candidate: Self.otherWindow, requester: nil, otherWindowsOfApp: [Self.otherWindow]))
    }
}
