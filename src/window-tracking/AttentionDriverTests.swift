import XCTest
import CoreGraphics

final class AttentionDriverTests: XCTestCase {
    private let pid: pid_t = 10
    private let otherPid: pid_t = 20

    /// Every wid belongs to `pid` and stands for itself, unless a test says otherwise.
    private func context(representatives: [CGWindowID: CGWindowID] = [:],
                         answerPending: Set<pid_t> = []) -> AttentionDriver.Context {
        AttentionDriver.Context(
            generation: { ProcessGeneration(pid: $0, generation: 1) },
            representativeOf: { representatives[$0] ?? $0 },
            frontmostPid: { nil },
            answerPending: { answerPending.contains($0) })
    }

    private func activated(_ driver: inout AttentionDriver, _ pid: pid_t) {
        _ = driver.decide(.appActivated(pid: pid, now: 0), context: context())
    }

    // MARK: what is, and is not, attention

    /// The load-bearing one: an 808 is not a member of the vocabulary at all, so it declines without needing
    /// a rule to decline with. Every WindowServer order and focus event maps to nothing.
    func testPhysicalEventsAreNotAttention() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        for input: ReducerInput in [.windowFocused(wid: 5, now: 1),
                                    .windowOrderedIn(wid: 5, now: 1, inSpaceTransition: false),
                                    .windowOrderedOut(wid: 5, inSpaceTransition: false),
                                    .zOrderRead(widsTopFirst: [5])] {
            let outcome = driver.decide(input, context: context())
            XCTAssertNil(outcome.wid, "\(input) moved the front")
            XCTAssertEqual(outcome.reason, "noInput")
        }
    }

    func testSpaceAndDiscoveryInputsNameNothing() {
        var driver = AttentionDriver()
        let outcome = driver.decide(.spacesSynced(windowToSpaces: [:], queried: [],
            answered: [], placedByWindowServer: [], topologyChanged: false), context: context())
        XCTAssertEqual(outcome.reason, "noInput")
    }

    // MARK: the two levels

    /// An activation of an app nobody has answered for is where the bounded read fires. R6: it is the one
    /// hole nothing else fills, because a plain activation names no window from any source.
    func testActivationWithNoFactAsksForARead() {
        var driver = AttentionDriver()
        let outcome = driver.decide(.appActivated(pid: pid, now: 0), context: context())
        XCTAssertNil(outcome.wid)
        XCTAssertEqual(outcome.reason, "needsRead")
        XCTAssertEqual(outcome.readPid, pid)
    }

    /// Repeated activations while the first bounded call is still in flight share that call. Besides saving
    /// IPC, this leaves one unambiguous issue sequence for the answer to consume.
    func testRepeatedFactlessActivationDoesNotDuplicateTheRead() {
        var driver = AttentionDriver()
        let first = driver.decide(.appActivated(pid: pid, now: 0), context: context())
        let second = driver.decide(.appActivated(pid: pid, now: 1), context: context())
        XCTAssertEqual(first.readPid, pid)
        XCTAssertNil(second.readPid)
        XCTAssertEqual(second.reason, "needsRead")
    }

    /// An app's own answer puts its window in front once that app is the front process.
    func testAnAppAnswerFrontsItsWindow() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        let outcome = driver.decide(.axFocusedWindowRead(pid: pid, wid: 2, viaActivationRead: false),
            context: context())
        XCTAssertEqual(outcome.wid, 2)
        XCTAssertEqual(outcome.reason, "front")
    }

    func testSemanticAnswerKeepsIngressOrderAcrossSettleDelay() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        let offer = driver.offerSemantic(pid: pid, wid: 1, context: context())!
        XCTAssertEqual(driver.decideDirected(pid: pid, wid: 2,
            context: context()).wid, 2)
        let late = driver.decideSemantic(offer, context: context())
        XCTAssertNil(late.wid)
        XCTAssertEqual(late.reason, "ignored.staleSequence")
        XCTAssertEqual(driver.attention.visibleFront?.wid, 2)
    }

    /// R2, every namer writes a fact and never a command: an answer from an app the user is NOT in records
    /// the fact and moves nothing. It is not refused, and it is not thrown away.
    func testAnAnswerFromABackgroundAppIsRecordedAndMovesNothing() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        let outcome = driver.decide(.axFocusedWindowRead(pid: otherPid, wid: 9, viaActivationRead: false),
            context: context())
        XCTAssertNil(outcome.wid)
        XCTAssertEqual(outcome.reason, "recorded")
    }

    /// ...and activating that app later lands on the window it named, with no read needed.
    func testTheRecordedFactIsWhatTheNextActivationLandsOn() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        _ = driver.decide(.axFocusedWindowRead(pid: otherPid, wid: 9, viaActivationRead: false),
            context: context())
        let outcome = driver.decide(.appActivated(pid: otherPid, now: 1),
            context: context())
        XCTAssertEqual(outcome.wid, 9)
        XCTAssertEqual(outcome.reason, "front")
        XCTAssertNil(outcome.readPid)
    }

    /// The model keeps the wid the app actually named, not only the tab representative that existed then.
    /// On a later activation the current group mapping is applied, so regrouping cannot stale the cache.
    func testCachedFactUsesTheCurrentRepresentative() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 8, viaActivationRead: true),
            context: context(representatives: [8: 3]))
        activated(&driver, otherPid)
        let outcome = driver.decide(.appActivated(pid: pid, now: 2),
            context: context(representatives: [8: 4]))
        XCTAssertEqual(outcome.wid, 4)
        XCTAssertEqual(outcome.observedWid, 8)
        XCTAssertNil(outcome.readPid)
    }

    /// The click names both levels at once, so it fronts a window of an app that has not activated yet. This
    /// is the only source that survives an app too busy to answer.
    func testAClickFrontsItsWindowWithoutWaitingForTheActivation() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        let outcome = driver.decideDirected(pid: otherPid, wid: 9,
            context: context())
        XCTAssertEqual(outcome.wid, 9)
    }

    /// #6055: AltTab's own switch names nothing. When the focus did not take, no activation follows, and the
    /// read AltTab makes of the target app afterwards is a fact about that app, so the front stays where the
    /// OS left it.
    func testAFocusThatDidNotTakeLeavesTheFrontAlone() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 2, viaActivationRead: false), context: context())
        let outcome = driver.decide(.axFocusedWindowRead(pid: otherPid, wid: 9, viaActivationRead: false),
            context: context())
        XCTAssertNil(outcome.wid)
        XCTAssertEqual(driver.attention.visibleFront?.wid, 2)
    }

    /// Picking another window of an app AltTab has just asked to switch: the activation arrives before the
    /// app has answered, and its cached answer is the window the user is leaving. Fronting that one would
    /// leave it at the top of the order until the real answer lands, and one tile from the next default pick.
    func testAnActivationWeAreStillWaitingOnDoesNotFrontTheCachedWindow() {
        var driver = AttentionDriver()
        activated(&driver, otherPid)
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 2, viaActivationRead: false), context: context())
        let activation = driver.decide(.appActivated(pid: pid, now: 1),
            context: context(answerPending: [pid]))
        XCTAssertNil(activation.wid)
        XCTAssertNil(activation.readPid, "the read that answers this one is already out")
        let answer = driver.decide(.axFocusedWindowRead(pid: pid, wid: 5, viaActivationRead: false),
            context: context())
        XCTAssertEqual(answer.wid, 5)
    }

    /// An app that answers with a background tab names the tile that stands for it, since that is what the
    /// switcher draws.
    func testAnAnswerMapsThroughTheTabRepresentative() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        let outcome = driver.decide(.axFocusedWindowRead(pid: pid, wid: 8, viaActivationRead: false),
            context: context(representatives: [8: 3]))
        XCTAssertEqual(outcome.wid, 3)
        XCTAssertEqual(outcome.observedWid, 8, "the tile is what moves; the wid the app named is reported")
    }

    /// R5, unknown is a value: an app that cannot say which of its windows is focused does not get one
    /// guessed for it from stacking order. The bounded read coming back empty is the one input that says so.
    func testAnAppThatCannotAnswerMovesNothing() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        let outcome = driver.decide(.axFocusedWindowReadFailed(pid: pid), context: context())
        XCTAssertNil(outcome.wid)
    }

    // MARK: process generations

    /// An app already running when AltTab started must not answer as a stale generation.
    func testUnseenPidIsRegisteredBeforeItsEvent() {
        var driver = AttentionDriver()
        let outcome = driver.decide(.appActivated(pid: pid, now: 0), context: context())
        XCTAssertEqual(outcome.reason, "needsRead")
    }

    /// A relaunched pid does not inherit the dead process's facts.
    func testRelaunchedPidDoesNotInheritTheDeadProcessesFact() {
        var driver = AttentionDriver()
        activated(&driver, pid)
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 2, viaActivationRead: false), context: context())
        driver.processExited(ProcessGeneration(pid: pid, generation: 1))
        let relaunched = AttentionDriver.Context(
            generation: { ProcessGeneration(pid: $0, generation: 2) },
            representativeOf: { $0 },
            frontmostPid: { nil },
            answerPending: { _ in false })
        let outcome = driver.decide(.appActivated(pid: pid, now: 1),
            context: relaunched)
        XCTAssertEqual(outcome.reason, "needsRead", "the new generation starts with no fact of its own")
    }

    /// R1, per-process monotonicity: the bounded read's answer carries the sequence it was ISSUED at, so an
    /// app that spoke for itself in the meantime keeps the last word.
    func testTheBoundedReadLosesToAnAnswerThatOvertookIt() {
        var driver = AttentionDriver()
        let outcome = driver.decide(.appActivated(pid: pid, now: 0), context: context())
        XCTAssertEqual(outcome.reason, "needsRead")
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 3, viaActivationRead: false), context: context())
        let late = driver.decide(.axFocusedWindowRead(pid: pid, wid: 1, viaActivationRead: true), context: context())
        XCTAssertEqual(late.reason, "ignored.staleSequence")
        XCTAssertEqual(driver.attention.visibleFront?.wid, 3)
    }

    /// A failed factless read is forgotten, and once the app later supplies a fact its next activation does
    /// not spend another IPC verifying the fact it just supplied.
    func testAFailedReadDoesNotCauseAnotherReadAfterTheAppAnswers() {
        var driver = AttentionDriver()
        XCTAssertEqual(driver.decide(.appActivated(pid: pid, now: 0),
            context: context()).reason, "needsRead")
        _ = driver.decide(.axFocusedWindowReadFailed(pid: pid), context: context())
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 3, viaActivationRead: false), context: context())
        XCTAssertEqual(driver.attention.visibleFront?.wid, 3)
        let next = driver.decide(.appActivated(pid: pid, now: 1), context: context())
        XCTAssertEqual(driver.attention.visibleFront?.wid, 3)
        XCTAssertNil(next.readPid)
    }

    /// Destroying the cached target clears the per-app fact. The next plain activation asks the app again
    /// instead of emitting attention for a wid the reducer can no longer apply.
    func testDestroyedCachedWindowMakesTheNextActivationReadAgain() {
        var driver = AttentionDriver()
        _ = driver.decide(.appActivated(pid: pid, now: 0), context: context())
        _ = driver.decide(.axFocusedWindowRead(pid: pid, wid: 3, viaActivationRead: true), context: context())
        _ = driver.decide(.windowDestroyed(wid: 3), context: context())
        let next = driver.decide(.appActivated(pid: pid, now: 1), context: context())
        XCTAssertEqual(next.reason, "needsRead")
        XCTAssertEqual(next.readPid, pid)
    }

    /// The observer already knows which process posted the notification. A recycled or not-yet-tracked wid
    /// must not be attributed through the current window table.
    func testSemanticAnswerUsesTheProvidersPid() {
        var driver = AttentionDriver()
        activated(&driver, otherPid)
        let offer = driver.offerSemantic(pid: otherPid, wid: 9, context: context())!
        let outcome = driver.decideSemantic(offer, context: context())
        XCTAssertEqual(outcome.wid, 9)
        XCTAssertEqual(driver.attention.visibleFront?.process.pid, otherPid)
    }

    // MARK: reason codes

    /// Every input maps to a reason code, so nothing can be attributed to "focus" in general.
    func testEveryInputHasADistinctReasonCode() {
        let inputs: [ReducerInput] = [
            .windowFocused(wid: 1, now: 0),
            .windowOrderedIn(wid: 1, now: 0, inSpaceTransition: false),
            .appActivated(pid: 1, now: 0),
            .axFocusedWindowRead(pid: 1, wid: 1, viaActivationRead: false),
            .axFocusedWindowRead(pid: 1, wid: 1, viaActivationRead: true),
            .axFocusedWindowReadFailed(pid: 1),
            .zOrderRead(widsTopFirst: []),
        ]
        let reasons = inputs.map { AttentionDriver.reason(for: $0) }
        XCTAssertEqual(reasons, ["ws808", "ws815", "activation", "axFocusedRead", "axActivationRead",
                                 "axReadFailed", "zOrderSeed"])
    }
}
