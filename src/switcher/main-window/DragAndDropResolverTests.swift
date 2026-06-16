import XCTest
import CoreGraphics

/// Pins drag-and-drop over the switcher as pure, deterministic decisions — no AppKit drag session, timers,
/// or event tap. Covers the four refinements from issue #5350 (no grab on appear, the movement deadzone,
/// the inter-tile gap targeting like hover, the always-on auto-select timer with its reset radius), the
/// drop's validity, and the regression fix: the mouse tap must yield the drop's mouseUp. Future refactors
/// of the drag pipeline must keep this green.
final class DragAndDropResolverTests: XCTestCase {

    // MARK: - A. Drag-over operation (deadzone, targeting, always-on timer)

    func testNoTargetReportsNoDrop() {
        // off the grid: no tile under the cursor → report no drop and clear hover
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: false, pastDeadzone: true, targetChanged: true, movedBeyondResetRadius: true), .noTarget)
    }

    func testTargetInDeadzoneLinksWithoutSelecting() {
        // a drag already in flight when the switcher appears must NOT grab a window on the first stray pixel
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: false, targetChanged: true, movedBeyondResetRadius: true), .inDeadzone)
    }

    func testTargetChangeArmsTimer() {
        // moving onto a different tile (re)arms the auto-select timer regardless of distance
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: true, movedBeyondResetRadius: false), .track(restartTimer: true))
    }

    func testSameTargetWithinRadiusKeepsTimerRunning() {
        // sub-radius jitter within the same tile lets the running timer fire (does not re-arm)
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: false, movedBeyondResetRadius: false), .track(restartTimer: false))
    }

    func testSameTargetBeyondRadiusRearmsTimer() {
        // leaving the reset radius within the same tile re-arms the timer
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: false, movedBeyondResetRadius: true), .track(restartTimer: true))
    }

    // MARK: - B. Auto-select timer reset radius (the 5px rule)

    func testNoAnchorAlwaysRearms() {
        // no anchor yet (timer not armed) → the first move arms it
        XCTAssertTrue(DragAndDropResolver.movedBeyondResetRadius(from: nil, to: CGPoint(x: 0, y: 0), resetRadius: 5))
    }

    func testWithinResetRadiusDoesNotRearm() {
        XCTAssertFalse(DragAndDropResolver.movedBeyondResetRadius(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 4, y: 0), resetRadius: 5))
    }

    func testAtResetRadiusRearms() {
        // boundary is inclusive (>=): exactly the radius re-arms
        XCTAssertTrue(DragAndDropResolver.movedBeyondResetRadius(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 5, y: 0), resetRadius: 5))
        // diagonal: 3-4-5 triangle is exactly the radius
        XCTAssertTrue(DragAndDropResolver.movedBeyondResetRadius(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 3, y: 4), resetRadius: 5))
    }

    func testBeyondResetRadiusRearms() {
        XCTAssertTrue(DragAndDropResolver.movedBeyondResetRadius(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 10), resetRadius: 5))
    }

    // MARK: - C. Mouse-up pass-through (the regression fix)

    func testPassesThroughMouseUpForUnseenDown() {
        // the fix: a drag's down was never seen (it started in another app before the switcher showed), so
        // the tap yields the drop's up — AppKit / the source app concludes it instead of the tap swallowing it
        XCTAssertTrue(DragAndDropResolver.passesThroughMouseUp(mouseDownWasSeen: false))
    }

    func testSwallowsMouseUpForSeenDown() {
        // a normal click's down WAS seen, so its up routes normally (select tile / dismiss), not yielded
        XCTAssertFalse(DragAndDropResolver.passesThroughMouseUp(mouseDownWasSeen: true))
    }

    // MARK: - D. Drop validity

    func testDropNeedsTargetWindowBundleAndUrls() {
        XCTAssertTrue(DragAndDropResolver.canDrop(hasTarget: true, hasWindow: true, hasAppBundleURL: true, urlCount: 1))
    }

    func testNoTargetRejectsDrop() {
        XCTAssertFalse(DragAndDropResolver.canDrop(hasTarget: false, hasWindow: true, hasAppBundleURL: true, urlCount: 1))
    }

    func testNoWindowRejectsDrop() {
        XCTAssertFalse(DragAndDropResolver.canDrop(hasTarget: true, hasWindow: false, hasAppBundleURL: true, urlCount: 1))
    }

    func testNoBundleUrlRejectsDrop() {
        XCTAssertFalse(DragAndDropResolver.canDrop(hasTarget: true, hasWindow: true, hasAppBundleURL: false, urlCount: 1))
    }

    func testNoUrlsRejectsDrop() {
        // a non-URL drag (text, image) or an empty pasteboard is rejected
        XCTAssertFalse(DragAndDropResolver.canDrop(hasTarget: true, hasWindow: true, hasAppBundleURL: true, urlCount: 0))
    }

    // MARK: - E. Use-case integration (the discussed scenarios as decision sequences)

    func testUseCaseDragPresentWhenSwitcherAppears() {
        // frame 1: cursor already over a tile when the switcher shows → no grab (deadzone not cleared)
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: false, targetChanged: true, movedBeyondResetRadius: true), .inDeadzone)
        // frame 2: after a few pixels the deadzone clears → now we select and arm the timer
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: true, movedBeyondResetRadius: true), .track(restartTimer: true))
    }

    func testUseCaseDropOnTileConcludes() {
        // dropping a file on a tile: the down wasn't seen → the tap yields the up, and the valid target drops
        XCTAssertTrue(DragAndDropResolver.passesThroughMouseUp(mouseDownWasSeen: false))
        XCTAssertTrue(DragAndDropResolver.canDrop(hasTarget: true, hasWindow: true, hasAppBundleURL: true, urlCount: 1))
    }

    func testUseCaseReleaseOnPaddingEndsDragWithoutOpening() {
        // releasing on the padding around the tiles (or outside the panel): the up is still yielded so the
        // drag concludes (no file left stuck on the cursor), but there's no tile target so nothing opens
        XCTAssertTrue(DragAndDropResolver.passesThroughMouseUp(mouseDownWasSeen: false))
        XCTAssertFalse(DragAndDropResolver.canDrop(hasTarget: false, hasWindow: false, hasAppBundleURL: false, urlCount: 1))
    }

    func testUseCaseBetweenTilesStillTargets() {
        // the 1px inter-tile gap resolves to a tile upstream (findTarget expands each tile by 1px), so the
        // kernel sees hasTarget == true and keeps tracking — never .noTarget while over the grid
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: false, movedBeyondResetRadius: false), .track(restartTimer: false))
    }

    func testUseCaseAutoSelectTimerSurvivesJitterButRearmsOnMove() {
        // dragging always runs the timer (no preference gate, unlike hover); jitter keeps it, a real move re-arms
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: false, movedBeyondResetRadius: false), .track(restartTimer: false))
        XCTAssertEqual(DragAndDropResolver.dragOver(hasTarget: true, pastDeadzone: true, targetChanged: false, movedBeyondResetRadius: true), .track(restartTimer: true))
    }
}
