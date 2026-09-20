import XCTest

final class CoalescedWorkTests: XCTestCase {
    private final class Queue {
        var now: UInt64 = 1_000_000_000
        var jobs = [(deadline: UInt64, work: () -> Void)]()

        func enqueue(_ delay: UInt64, _ work: @escaping () -> Void) {
            jobs.append((now + delay, work))
        }

        func runNext() {
            let job = jobs.removeFirst()
            now = max(now, job.deadline)
            job.work()
        }
    }

    func testOverdueRepaintStillCoalescesUntilItsBlockRuns() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        var paints = 0
        for _ in 0..<5 {
            coalescer.request { paints += 1 }
            queue.now += 25_000_000
        }
        XCTAssertEqual(queue.jobs.count, 1)
        queue.runNext()
        XCTAssertEqual(paints, 1)
        XCTAssertTrue(queue.jobs.isEmpty)
        coalescer.request { paints += 1 }
        queue.runNext()
        XCTAssertEqual(paints, 2)
    }

    func testReentrantRepaintWaitsForTheCompletedPaintsQuietPeriod() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        var paints = 0
        coalescer.request {
            paints += 1
            coalescer.request { paints += 1 }
            queue.now += 21_000_000
        }
        queue.runNext()
        let quietEnds = queue.now + 84_000_000
        queue.runNext()
        XCTAssertEqual(paints, 1)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.deadline, quietEnds)
        coalescer.request { XCTFail("A re-armed repaint still owns the pending block") }
        XCTAssertEqual(queue.jobs.count, 1)
        queue.runNext()
        XCTAssertEqual(paints, 2)
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testWindowBurstSharesOneRepaint() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        var paints = 0
        for _ in 0..<34 {
            coalescer.request { paints += 1 }
            queue.now += 400_000
        }
        XCTAssertEqual(queue.jobs.count, 1)
        queue.runNext()
        XCTAssertEqual(paints, 1)
    }

    func testAttentionReconcilesSelectionBeforeReleaseDuringRepaintQuietPeriod() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        var order = [1, 2]
        var paints = 0
        coalescer.request { queue.now += 50_000_000 }
        queue.runNext()
        coalescer.request { XCTFail("Attention superseded this structural repaint") }
        coalescer.requestImmediately {
            order = [2, 1]
            paints += 1
        }
        queue.now += 20_000_000
        XCTAssertEqual(order[1], 1, "Release must leave the newly focused window 2 even before the queued paint")
        queue.runNext()
        XCTAssertEqual(paints, 1)
    }

    func testReleaseFollowsSelectionWhileRemovalRepaintIsPending() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        let session = SwitcherSession()
        session.selectedIndex = 2
        session.selectedTarget = "c"
        var windows = ["a", "b", "c", "d"]
        windows.remove(at: 1)
        coalescer.request { session.selectedIndex = 1 }
        XCTAssertEqual(session.selectedIndex, 2)
        XCTAssertEqual(SelectionResolver.selectedWindow(in: windows, at: session.selectedIndex,
            target: session.selectedTarget, id: { $0 }), "c")
        queue.runNext()
        XCTAssertEqual(SelectionResolver.selectedWindow(in: windows, at: session.selectedIndex,
            target: session.selectedTarget, id: { $0 }), "c")
    }

    func testCancelledTailCannotStealTheNextRepaintsSlot() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        var paints = 0
        coalescer.request { XCTFail("Superseded repaint ran") }
        coalescer.requestImmediately { paints += 1 }
        coalescer.request { paints += 1 }
        queue.runNext()
        coalescer.request { XCTFail("The newer repaint must still own its slot") }
        XCTAssertEqual(queue.jobs.count, 1)
        queue.runNext()
        XCTAssertEqual(paints, 2)
    }

    func testRequestDuringImmediatePaintWaitsForItsMeasuredCost() {
        let queue = Queue()
        let coalescer = RepaintCoalescer(now: { queue.now }, enqueue: queue.enqueue)
        var paints = 0
        coalescer.requestImmediately {
            coalescer.request { paints += 1 }
            queue.now += 50_000_000
        }
        queue.runNext()
        XCTAssertEqual(paints, 0)
        queue.runNext()
        XCTAssertEqual(paints, 1)
    }

    func testSlowReadRetainsOneFollowUpAndAppliesEveryCompletedBatch() {
        let queue = Queue()
        var batches = [Set<Int>]()
        var completions = [() -> Void]()
        var applied = 0
        let coalescer = BatchCoalescer<Int>(enqueue: { queue.enqueue(0, $0) }) { batch, finish in
            batches.append(batch)
            completions.append {
                applied += 1
                finish()
            }
        }
        coalescer.request([1])
        coalescer.request([2])
        XCTAssertEqual(queue.jobs.count, 1)
        queue.runNext()
        XCTAssertEqual(batches, [[1, 2]])
        for _ in 0..<1000 { coalescer.request([1, 3]) }
        XCTAssertTrue(coalescer.accepts(1), "Geometry input must not starve the active read")
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(batches.count, 1)
        completions.removeFirst()()
        XCTAssertEqual(applied, 1)
        XCTAssertEqual(queue.jobs.count, 1)
        queue.runNext()
        XCTAssertEqual(batches, [[1, 2], [1, 3]])
        for _ in 0..<1000 { coalescer.request([1]) }
        completions.removeFirst()()
        XCTAssertEqual(applied, 2)
        queue.runNext()
        XCTAssertEqual(batches.last, [1])
        completions.removeFirst()()
        XCTAssertEqual(applied, 3)
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testSemanticEventInvalidatesOnlyItsWindowUntilTheFollowUpStarts() {
        let queue = Queue()
        var finishes = [() -> Void]()
        let coalescer = BatchCoalescer<CGWindowID>(enqueue: { queue.enqueue(0, $0) }) { _, finish in
            finishes.append(finish)
        }
        coalescer.request([1, 2])
        queue.runNext()
        coalescer.invalidate(ReducerInput.windowOrderedOut(wid: 1, inSpaceTransition: false).invalidatedWindowStateReads)
        coalescer.request([1])
        XCTAssertFalse(coalescer.accepts(1))
        XCTAssertTrue(coalescer.accepts(2))
        finishes.removeFirst()()
        XCTAssertFalse(coalescer.accepts(2), "Finished batches must not retain window identities")
        queue.runNext()
        XCTAssertTrue(coalescer.accepts(1))
        finishes.removeFirst()()
    }

    func testOldQueryCannotUndoANewerOrderInOrOrderOut() {
        for initiallyVisible in [false, true] {
            let queue = Queue()
            var state = visibilityState(initiallyVisible)
            var complete: (() -> Void)?
            var coalescer: BatchCoalescer<CGWindowID>!
            coalescer = BatchCoalescer(enqueue: { queue.enqueue(0, $0) }) { _, finish in
                let snapshot = WsWindowSnapshot(wid: 1, position: .zero, size: CGSize(width: 800, height: 600),
                    isFullscreen: false, isVisible: initiallyVisible)
                complete = {
                    if coalescer.accepts(snapshot.wid) {
                        _ = WindowEventReducer.reduce(&state, .windowServerStateRead([snapshot]))
                    }
                    finish()
                }
            }
            coalescer.request([1])
            queue.runNext()
            let event: ReducerInput = initiallyVisible ? .windowOrderedOut(wid: 1, inSpaceTransition: false)
                : .windowOrderedIn(wid: 1, now: 1, inSpaceTransition: false)
            coalescer.invalidate(event.invalidatedWindowStateReads)
            let effects = WindowEventReducer.reduce(&state, event)
            for effect in effects {
                if case .queryWindowServerState(let wids) = effect { coalescer.request(Set(wids)) }
            }
            XCTAssertEqual(state.window(1)?.isOrderedIn, !initiallyVisible)
            complete?()
            XCTAssertEqual(state.window(1)?.isOrderedIn, !initiallyVisible,
                "An old snapshot cannot undo the semantic edge while its follow-up is queued")
            XCTAssertEqual(queue.jobs.count, 1)
        }
    }

    func testLifecycleSpaceAndAttentionFenceReadsButGeometryDoesNot() {
        XCTAssertEqual(ReducerInput.windowDestroyed(wid: 1).invalidatedWindowStateReads, [1])
        XCTAssertEqual(ReducerInput.livenessConfirmedDead(wid: 1).invalidatedWindowStateReads, [1])
        XCTAssertEqual(ReducerInput.spaceMembershipChanged(wid: 1, spaceId: 2, added: true,
            now: 1, inSpaceTransition: true).invalidatedWindowStateReads, [1])
        XCTAssertEqual(ReducerInput.attentionCommitted(wid: 1, observed: 2, at: 1).invalidatedWindowStateReads, [1, 2])
        XCTAssertTrue(ReducerInput.windowMovedOrResized(wid: 1, inSpaceTransition: false).invalidatedWindowStateReads.isEmpty)
    }

    private func visibilityState(_ visible: Bool) -> TrackedWindowState {
        var state = TrackedWindowState()
        var window = TrackedWindow(id: "wid-1", wid: 1, pid: 42, title: "A",
            size: CGSize(width: 800, height: 600), position: .zero,
            spaceIds: [1], spaceIndexes: [1], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: false, isMainWindow: true,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: 0,
            creationOrder: 0, hasThumbnail: true)
        window.isOrderedIn = visible
        state.windows = [window]
        state.apps[42] = TrackedApp(state: ApplicationState(pid: 42, bundleIdentifier: "test.app",
            localizedName: "Test", isHidden: false), isActive: true)
        state.visibleSpaces = [1]
        state.currentSpaceId = 1
        state.spaceIndexById = [1: 1]
        state.frontmostPid = 42
        return state
    }

    func testEmptyReadAnswerStillReleasesPendingWork() {
        let queue = Queue()
        var finishes = [() -> Void]()
        let coalescer = BatchCoalescer<Int>(enqueue: { queue.enqueue(0, $0) }) { _, finish in
            finishes.append(finish)
        }
        coalescer.request([])
        XCTAssertTrue(queue.jobs.isEmpty)
        coalescer.request([1])
        queue.runNext()
        coalescer.request([2])
        finishes.removeFirst()()
        queue.runNext()
        XCTAssertEqual(finishes.count, 1)
        finishes.removeFirst()()
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testRequestsDuringApplyAreRetainedInTheNextRead() {
        let queue = Queue()
        var coalescer: BatchCoalescer<Int>!
        var batches = [Set<Int>]()
        coalescer = BatchCoalescer(enqueue: { queue.enqueue(0, $0) }) { batch, finish in
            batches.append(batch)
            if batches.count == 1 { coalescer.request([2]) }
            finish()
        }
        coalescer.request([1])
        queue.runNext()
        queue.runNext()
        XCTAssertEqual(batches, [[1], [2]])
        XCTAssertTrue(queue.jobs.isEmpty)
    }
}
