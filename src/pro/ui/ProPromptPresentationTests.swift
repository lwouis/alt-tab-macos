import XCTest

final class ProPromptPresentationTests: XCTestCase {
    func testUnavailableHistoryShowsFallbackOnceAndIgnoresLateHistory() {
        var deadline: DispatchWorkItem?
        let presentation = ProPromptPresentation(scheduleTimeout: { deadline = $0 })
        var complete: ((Int) -> Void)?
        var shown = [Int]()
        presentation.load(using: { complete = $0 }, fallback: 0, canPresent: { true }, show: { shown.append($0) })
        XCTAssertTrue(presentation.isPending)
        deadline?.perform()
        XCTAssertEqual(shown, [0])
        XCTAssertFalse(presentation.isPending)
        complete?(42)
        XCTAssertEqual(shown, [0])
    }

    func testHistoryArrivingBeforeDeadlineKeepsItsEvidence() {
        var deadline: DispatchWorkItem?
        let presentation = ProPromptPresentation(scheduleTimeout: { deadline = $0 })
        var shown = [Int]()
        presentation.load(using: { $0(42) }, fallback: 0, canPresent: { true }, show: { shown.append($0) })
        XCTAssertEqual(deadline?.isCancelled, true)
        deadline?.perform()
        XCTAssertEqual(shown, [42])
    }

    func testHistoryTimeoutRechecksEligibilityAndCannotReviveCancelledRequest() {
        for cancelled in [false, true] {
            var deadline: DispatchWorkItem?
            let presentation = ProPromptPresentation(scheduleTimeout: { deadline = $0 })
            var allowed = true
            presentation.load(using: { (_: @escaping (Int) -> Void) in }, fallback: 0,
                              canPresent: { allowed }, show: { _ in XCTFail("The expired request must stay hidden") })
            if cancelled { presentation.cancel() } else { allowed = false }
            deadline?.perform()
            XCTAssertFalse(presentation.isPending)
        }
    }

    func testHistoryCompletionRechecksEveryProactiveBlocker() {
        for blocker in [\ProPromptPresentation.Context.sessionAvailable, \.isPro, \.switcherActive,
                        \.onboarding, \.competingUI, \.fullscreen, \.optedOut, \.messageToday] {
            let presentation = ProPromptPresentation()
            var context = ProPromptPresentation.Context()
            var complete: ((Int) -> Void)?
            var shown = false
            presentation.load(using: { complete = $0 }, canPresent: { context.allows(userInitiated: false) },
                              show: { _ in shown = true })
            XCTAssertTrue(presentation.isPending)
            context[keyPath: blocker].toggle()
            complete?(1)
            XCTAssertFalse(shown, "Must recheck \(blocker) after reading history")
            XCTAssertFalse(presentation.isPending)
        }
    }

    func testCancelledHistoryDoesNotReappearAfterUnlockOrClosingSettings() {
        let presentation = ProPromptPresentation()
        var complete: ((Int) -> Void)?
        var shown = false
        presentation.load(using: { complete = $0 }, canPresent: { true }, show: { _ in shown = true })
        presentation.cancel()
        complete?(1)
        XCTAssertFalse(shown)
        XCTAssertFalse(presentation.isPending)
    }

    func testNewRequestReplacesOldHistoryAndOnlyPresentsOnce() {
        let presentation = ProPromptPresentation()
        var first: ((Int) -> Void)?
        var second: ((Int) -> Void)?
        var shown = [Int]()
        presentation.load(using: { first = $0 }, canPresent: { true }, show: { shown.append($0) })
        presentation.load(using: { second = $0 }, canPresent: { true }, show: { shown.append($0) })
        first?(1)
        XCTAssertTrue(presentation.isPending)
        second?(2)
        second?(2)
        XCTAssertEqual(shown, [2])
        XCTAssertFalse(presentation.isPending)
    }

    func testCancellationDuringEligibilityCheckCannotReviveTheRequest() {
        let presentation = ProPromptPresentation()
        var complete: ((Int) -> Void)?
        var cancelDuringCheck = false
        presentation.load(using: { complete = $0 }, canPresent: {
            if cancelDuringCheck { presentation.cancel() }
            return true
        }, show: { _ in XCTFail("A context check must not revive a cancelled request") })
        cancelDuringCheck = true
        complete?(1)
        XCTAssertFalse(presentation.isPending)
    }

    func testBlockedRequestsDoNotReadHistory() {
        let presentation = ProPromptPresentation()
        presentation.load(using: { (_: @escaping (Int) -> Void) in XCTFail("Must not load history") },
                          canPresent: { false }, show: { _ in XCTFail("Must not present") })
        XCTAssertFalse(presentation.isPending)
    }

    func testUserInitiatedFeedbackIgnoresMarketingLimitsButStillRequiresAnAvailableSession() {
        var context = ProPromptPresentation.Context(competingUI: true, fullscreen: true, optedOut: true, messageToday: true)
        XCTAssertTrue(context.allows(userInitiated: true))
        XCTAssertFalse(context.allows(userInitiated: false))
        for blocker in [\ProPromptPresentation.Context.sessionAvailable, \.isPro, \.switcherActive, \.onboarding] {
            context[keyPath: blocker].toggle()
            XCTAssertFalse(context.allows(userInitiated: true))
            context[keyPath: blocker].toggle()
        }
    }
}
