import XCTest

/// Pins the sequencing of the first-run permissions window: which of the two steps is live, how each
/// step's card collapses or expands, and when the bottom bar offers "Continue without thumbnails".
///
/// The window walks one step at a time — Accessibility first (mandatory, the only alternative is
/// quitting), then Screen Recording (waivable, `.skipped` resolves it like `.granted`). Every card
/// state is recomputed from the two live `PermissionStatus` values rather than from a stored cursor,
/// so revoking a permission walks the sequence backwards instead of stranding the user on a step.
final class PermissionFlowTests: XCTestCase {

    // MARK: - Fresh launch

    /// Nothing granted → the user is on Accessibility.
    func testFreshLaunchStartsOnAccessibility() {
        XCTAssertEqual(PermissionFlow.liveStep(accessibility: .notGranted, screenRecording: .notGranted), .accessibility)
    }

    /// Screen Recording is `.notGranted` too, but it is not the live step, so it collapses.
    func testFreshLaunchCollapsesScreenRecordingAsUpcoming() {
        XCTAssertEqual(PermissionFlow.state(of: .screenRecording, accessibility: .notGranted, screenRecording: .notGranted), .upcoming)
    }

    /// The live step is the expanded one.
    func testFreshLaunchExpandsAccessibilityAsLive() {
        XCTAssertEqual(PermissionFlow.state(of: .accessibility, accessibility: .notGranted, screenRecording: .notGranted), .live)
    }

    // MARK: - Advancing

    /// Granting Accessibility advances to Screen Recording.
    func testAccessibilityGrantedMovesToScreenRecording() {
        XCTAssertEqual(PermissionFlow.liveStep(accessibility: .granted, screenRecording: .notGranted), .screenRecording)
    }

    /// The finished step shrinks to its title row.
    func testGrantedAccessibilityCollapsesAsDone() {
        XCTAssertEqual(PermissionFlow.state(of: .accessibility, accessibility: .granted, screenRecording: .notGranted), .done)
    }

    /// Both granted → nothing left; the window closes.
    func testBothGrantedHasNoLiveStep() {
        XCTAssertNil(PermissionFlow.liveStep(accessibility: .granted, screenRecording: .granted))
    }

    // MARK: - Waiving Screen Recording

    /// "Continue without thumbnails" persists `.skipped`, which resolves the step.
    func testSkippedScreenRecordingHasNoLiveStep() {
        XCTAssertNil(PermissionFlow.liveStep(accessibility: .granted, screenRecording: .skipped))
    }

    /// A waived step reads as finished, not as still pending.
    func testSkippedScreenRecordingIsDone() {
        XCTAssertEqual(PermissionFlow.state(of: .screenRecording, accessibility: .granted, screenRecording: .skipped), .done)
    }

    // MARK: - Revocation walks backwards

    /// Losing Accessibility mid-flow sends the user back to step 1.
    func testRevokedAccessibilityReturnsToStepOne() {
        XCTAssertEqual(PermissionFlow.liveStep(accessibility: .notGranted, screenRecording: .granted), .accessibility)
    }

    /// The already-granted second step stays `.done` while step 1 is live again — it is finished,
    /// just not reachable, which is different from never having been reached.
    func testRevokedAccessibilityCollapsesGrantedScreenRecordingAsDone() {
        XCTAssertEqual(PermissionFlow.state(of: .screenRecording, accessibility: .notGranted, screenRecording: .granted), .done)
    }

    // MARK: - The waive option

    /// Offered on the Screen Recording step only.
    func testWaiveOfferedOnlyOnScreenRecordingStep() {
        XCTAssertTrue(PermissionFlow.showsWaiveOption(accessibility: .granted, screenRecording: .notGranted))
        XCTAssertFalse(PermissionFlow.showsWaiveOption(accessibility: .notGranted, screenRecording: .notGranted))
        XCTAssertFalse(PermissionFlow.showsWaiveOption(accessibility: .notGranted, screenRecording: .granted))
    }

    /// Nothing to waive once the flow is resolved.
    func testWaiveNotOfferedWhenComplete() {
        XCTAssertFalse(PermissionFlow.showsWaiveOption(accessibility: .granted, screenRecording: .granted))
        XCTAssertFalse(PermissionFlow.showsWaiveOption(accessibility: .granted, screenRecording: .skipped))
    }

    // MARK: - Completion

    /// `isComplete` is exactly "no live step", over the whole grid of inputs.
    func testCompleteOnlyWhenNoLiveStep() {
        let statuses: [PermissionStatus] = [.granted, .notGranted, .skipped]
        for accessibility in statuses {
            for screenRecording in statuses {
                XCTAssertEqual(
                    PermissionFlow.isComplete(accessibility: accessibility, screenRecording: screenRecording),
                    PermissionFlow.liveStep(accessibility: accessibility, screenRecording: screenRecording) == nil,
                    "accessibility:\(accessibility) screenRecording:\(screenRecording)")
            }
        }
    }

    // MARK: - After launch

    /// A skipped Screen Recording offers to grant after all.
    func testSkippedScreenRecordingOffersGrant() {
        XCTAssertTrue(PermissionFlow.offersGrantAfterSkip(.screenRecording, accessibility: .granted, screenRecording: .skipped))
    }

    /// Only a skip is reversed from the card: a granted or pending step, or Accessibility, never offers it.
    func testOnlySkippedScreenRecordingOffersGrant() {
        XCTAssertFalse(PermissionFlow.offersGrantAfterSkip(.screenRecording, accessibility: .granted, screenRecording: .granted))
        XCTAssertFalse(PermissionFlow.offersGrantAfterSkip(.screenRecording, accessibility: .granted, screenRecording: .notGranted))
        XCTAssertFalse(PermissionFlow.offersGrantAfterSkip(.accessibility, accessibility: .granted, screenRecording: .skipped))
    }

    /// While Accessibility is missing, it is the step to act on; the skip stays as it is.
    func testSkippedScreenRecordingWaitsForAccessibility() {
        XCTAssertFalse(PermissionFlow.offersGrantAfterSkip(.screenRecording, accessibility: .notGranted, screenRecording: .skipped))
    }

    /// The bar's main button grants while a step is live, and closes once nothing is left.
    func testPrimaryActionGrantsUntilCompleteThenCloses() {
        XCTAssertEqual(PermissionFlow.primaryAction(accessibility: .notGranted, screenRecording: .notGranted), .grant)
        XCTAssertEqual(PermissionFlow.primaryAction(accessibility: .granted, screenRecording: .notGranted), .grant)
        XCTAssertEqual(PermissionFlow.primaryAction(accessibility: .granted, screenRecording: .granted), .close)
        XCTAssertEqual(PermissionFlow.primaryAction(accessibility: .granted, screenRecording: .skipped), .close)
    }
}
