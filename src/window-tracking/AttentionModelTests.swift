import XCTest

final class AttentionModelTests: XCTestCase {
    private let p1 = ProcessGeneration(pid: 10, generation: 1)
    private let p1Relaunched = ProcessGeneration(pid: 10, generation: 2)
    private let p2 = ProcessGeneration(pid: 20, generation: 1)

    private func wid(_ process: ProcessGeneration, _ wid: UInt32) -> WindowIdentity {
        WindowIdentity(process: process, wid: wid)
    }

    private func seq(_ raw: UInt64) -> IngressSequence { IngressSequence(rawValue: raw) }

    private func state() -> AttentionModelState {
        var state = AttentionModelState()
        for process in [p1, p2] { _ = AttentionModel.reduce(&state, .processStarted(process)) }
        return state
    }

    @discardableResult
    private func name(_ state: inout AttentionModelState, _ namer: AttentionNamer, _ target: WindowIdentity,
                      _ sequence: UInt64) -> AttentionModelDecision {
        AttentionModel.reduce(&state, .named(namer, observed: target, representative: target, seq(sequence)))
    }

    /// The two levels are separate: an app answering about itself records a fact, and only activating that app
    /// makes the fact visible.
    func testAnswerFromABackgroundAppRecordsAFactAndMovesNothing() {
        var state = state()
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        name(&state, .app, wid(p1, 1), 2)
        XCTAssertEqual(name(&state, .app, wid(p2, 7), 3), .recorded(wid(p2, 7)))
        XCTAssertEqual(state.visibleFront, wid(p1, 1))
        XCTAssertEqual(AttentionModel.reduce(&state, .frontProcessChanged(p2)), .front(wid(p2, 7)))
    }

    /// R6: an activation naming no window is the one hole nothing else fills, so it asks for one read.
    func testActivationWithNoFactAsksForOneBoundedRead() {
        var state = state()
        XCTAssertEqual(AttentionModel.reduce(&state, .frontProcessChanged(p1)), .readFocusedWindow(p1))
        XCTAssertNil(state.visibleFront)
        XCTAssertEqual(state.currentUserContext, .application(p1))
    }

    /// ...and an activation that already has an answer asks for nothing.
    func testActivationWithAFactMovesTheFrontWithoutReading() {
        var state = state()
        name(&state, .app, wid(p1, 1), 2)
        XCTAssertEqual(AttentionModel.reduce(&state, .frontProcessChanged(p1)), .front(wid(p1, 1)))
    }

    /// A lifecycle edge invalidates a cached answer instead of letting a later activation resurrect a wid
    /// that no longer exists.
    func testInvalidatedWindowMakesTheNextActivationReadAgain() {
        var state = state()
        name(&state, .app, wid(p1, 1), 2)
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        XCTAssertEqual(AttentionModel.reduce(&state, .windowInvalidated(1)), .none)
        XCTAssertNil(state.visibleFront)
        XCTAssertEqual(AttentionModel.reduce(&state, .frontProcessChanged(p1)), .readFocusedWindow(p1))
    }

    /// The click names the app and the window in the same breath, 11 ms before NSWorkspace says anything.
    func testClickCarriesBothLevels() {
        var state = state()
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        XCTAssertEqual(name(&state, .click, wid(p2, 7), 2), .front(wid(p2, 7)))
        XCTAssertEqual(state.frontProcess, p2)
        XCTAssertEqual(state.currentUserContext, .window(wid(p2, 7)))
    }

    /// R2: the app talks about itself only. A late answer from the app the user left cannot take the front.
    func testAnAppAnswerNeverChangesWhichAppIsInFront() {
        var state = state()
        name(&state, .click, wid(p2, 7), 2)
        XCTAssertEqual(name(&state, .app, wid(p1, 1), 3), .recorded(wid(p1, 1)))
        XCTAssertEqual(state.frontProcess, p2)
        XCTAssertEqual(state.visibleFront, wid(p2, 7))
    }

    /// R4 needs no rule of its own: the click is a prediction, the app's answer is the outcome, and the
    /// outcome arrives later.
    func testTheAppCorrectsTheClickBecauseItArrivesLater() {
        var state = state()
        XCTAssertEqual(name(&state, .click, wid(p1, 1), 2), .front(wid(p1, 1)))
        XCTAssertEqual(name(&state, .app, wid(p1, 3), 3), .front(wid(p1, 3)))
    }

    /// R1 has teeth for exactly one source: the bounded read is issued at the activation and lands after
    /// whatever the app said in the meantime, so it carries the older sequence and loses.
    func testTheBoundedReadCannotOverwriteAFresherAnswerFromItsOwnApp() {
        var state = state()
        name(&state, .app, wid(p1, 3), 9)
        XCTAssertEqual(name(&state, .activationRead, wid(p1, 1), 4), .ignored(.staleSequence))
        XCTAssertEqual(state.focusedWindow[p1]?.target, wid(p1, 3))
    }

    /// ...and no teeth at all across processes: one app's sequence says nothing about another's.
    func testAcrossProcessesNothingIsCompared() {
        var state = state()
        name(&state, .app, wid(p2, 7), 9)
        XCTAssertEqual(name(&state, .app, wid(p1, 1), 4), .recorded(wid(p1, 1)))
        XCTAssertEqual(state.focusedWindow[p1]?.target, wid(p1, 1))
    }

    /// R5: an empty read is not evidence against what the app already said.
    func testAnUnknownReadNeitherMovesNorErasesTheFront() {
        var state = state()
        name(&state, .app, wid(p1, 1), 2)
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        XCTAssertEqual(AttentionModel.reduce(&state, .focusedWindowUnknown(p1)), .none)
        XCTAssertEqual(state.visibleFront, wid(p1, 1))
    }

    /// The front app that has never answered reads as nil, and nil is "nobody has said". A consumer writing
    /// this value through would clear the order on every activation.
    func testTheVisibleFrontIsNilWhileTheFrontAppHasNotAnswered() {
        var state = state()
        name(&state, .app, wid(p1, 1), 2)
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p2))
        XCTAssertNil(state.visibleFront)
        XCTAssertEqual(state.focusedWindow[p1]?.target, wid(p1, 1))
        XCTAssertEqual(state.currentUserContext, .application(p2))
    }

    /// A window enters as the one that stands for it in the switcher.
    func testTheRepresentativeIsWhatLandsInTheFact() {
        var state = state()
        _ = AttentionModel.reduce(&state, .named(.app, observed: wid(p1, 5),
                                                 representative: wid(p1, 1), seq(2)))
        XCTAssertEqual(state.focusedWindow[p1]?.target, wid(p1, 1))
    }

    /// A missing or cross-process representative is refused rather than guessed.
    func testAnIneligibleTargetIsRefused() {
        var state = state()
        XCTAssertEqual(AttentionModel.reduce(&state, .named(.app, observed: wid(p1, 5),
                                                            representative: nil, seq(2))),
                       .ignored(.ineligible))
        XCTAssertEqual(AttentionModel.reduce(&state, .named(.app, observed: wid(p1, 5),
                                                            representative: wid(p2, 5), seq(3))),
                       .ignored(.ineligible))
        XCTAssertTrue(state.focusedWindow.isEmpty)
    }

    /// A callback from a dead process must not look current to a rule keyed on identity.
    func testAStaleGenerationIsRefused() {
        var state = state()
        XCTAssertEqual(name(&state, .app, wid(p1Relaunched, 1), 2), .ignored(.staleGeneration))
        XCTAssertEqual(AttentionModel.reduce(&state, .frontProcessChanged(p1Relaunched)),
                       .ignored(.staleGeneration))
    }

    /// A reused pid is a new identity, and it inherits nothing.
    func testARelaunchedPidForgetsThePreviousGenerationsFact() {
        var state = state()
        name(&state, .click, wid(p1, 1), 2)
        _ = AttentionModel.reduce(&state, .processStarted(p1Relaunched))
        XCTAssertNil(state.focusedWindow[p1])
        XCTAssertNil(state.frontProcess)
        XCTAssertNil(state.visibleFront)
    }

    /// An exit releases the front rather than handing it to a neighbour: macOS will say who is next.
    func testProcessExitForgetsItsFactAndReleasesTheFront() {
        var state = state()
        name(&state, .click, wid(p1, 1), 2)
        name(&state, .app, wid(p2, 7), 3)
        XCTAssertEqual(AttentionModel.reduce(&state, .processExited(p1)), .none)
        XCTAssertNil(state.frontProcess)
        XCTAssertNil(state.visibleFront)
        XCTAssertEqual(state.focusedWindow[p2]?.target, wid(p2, 7))
        XCTAssertEqual(state.currentUserContext, .unknown)
    }

    func testLastAttendedWindowIsPerLiveApplication() {
        var state = state()
        name(&state, .app, wid(p1, 1), 2)
        name(&state, .click, wid(p2, 7), 3)
        XCTAssertEqual(state.lastAttendedWindow(p1.pid), wid(p1, 1))
        XCTAssertEqual(state.lastAttendedWindow(p2.pid), wid(p2, 7))
        XCTAssertNil(state.lastAttendedWindow(999))
    }

    /// #5974's shape: an app raising all its windows emits one true answer per window, 0.6 ms apart, and ends
    /// on the window it started on. Taking every answer still lands there, which is why the settle needs
    /// nothing guessed in advance and taken back afterwards.
    func testARaiseBurstEndsWhereItStarted() {
        var state = state()
        name(&state, .app, wid(p1, 1), 2)
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        for (index, target) in [wid(p1, 1), wid(p1, 2), wid(p1, 3), wid(p1, 1)].enumerated() {
            name(&state, .app, target, UInt64(3 + index))
        }
        XCTAssertEqual(state.visibleFront, wid(p1, 1))
    }

    /// Naming the window that already holds the front is a fact, not a move.
    func testNamingTheWindowThatAlreadyHoldsTheFrontMovesNothing() {
        var state = state()
        name(&state, .click, wid(p1, 1), 2)
        XCTAssertEqual(name(&state, .app, wid(p1, 1), 3), .recorded(wid(p1, 1)))
    }

    /// The measured stale-answer race: the app changed its key window, wedged
    /// with that notification queued, and the user clicked a different window. At the unwedge the stale
    /// answer comes out FIRST and the app's report of the click's own outcome comes out LAST, all inside
    /// 11 ms. Arrival order alone resolves it, which is why no "the click holds its target" guard exists.
    func testAStaleAnswerFlushedByAnUnwedgeLosesToTheClicksOutcome() {
        var state = state()
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        XCTAssertEqual(name(&state, .app, wid(p1, 8), 2), .front(wid(p1, 8)))
        XCTAssertEqual(name(&state, .click, wid(p1, 9), 3), .front(wid(p1, 9)))
        XCTAssertEqual(name(&state, .app, wid(p1, 9), 4), .recorded(wid(p1, 9)))
        XCTAssertEqual(state.visibleFront, wid(p1, 9))
    }

    /// The user picked p2's window 7 while p2 last answered window 8. Fronting 8 on the activation would put
    /// the window they are LEAVING p2 for at the top of the order, one tile from the next summon's default
    /// pick — and the read that says 7 is already out.
    func testAnActivationAwaitingAnAnswerNeitherFrontsNorReads() {
        var state = state()
        name(&state, .app, wid(p2, 8), 2)
        name(&state, .app, wid(p1, 1), 3)
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        XCTAssertEqual(AttentionModel.reduce(&state, .frontProcessChangedAwaitingAnswer(p2)), .none)
        XCTAssertEqual(state.frontProcess, p2)
        XCTAssertEqual(name(&state, .app, wid(p2, 7), 4), .front(wid(p2, 7)))
    }

    /// Switching back into the window an app was already on: the answer names the cached window, and it is
    /// still a move, because the activation before it declined to make one.
    func testTheAwaitedAnswerMovesTheFrontEvenNamingTheCachedWindow() {
        var state = state()
        name(&state, .app, wid(p2, 8), 2)
        name(&state, .app, wid(p1, 1), 3)
        _ = AttentionModel.reduce(&state, .frontProcessChanged(p1))
        _ = AttentionModel.reduce(&state, .frontProcessChangedAwaitingAnswer(p2))
        XCTAssertEqual(name(&state, .app, wid(p2, 8), 4), .front(wid(p2, 8)))
        // and the debt is settled: the next repeat of that answer is an ordinary fact again
        XCTAssertEqual(name(&state, .app, wid(p2, 8), 5), .recorded(wid(p2, 8)))
    }
}
