import XCTest

final class AxObserverHealthTests: XCTestCase {
    private let process = ProcessGeneration(pid: 42, generation: 1)
    private let replacement = ProcessGeneration(pid: 42, generation: 2)
    private let other = ProcessGeneration(pid: 84, generation: 1)
    private let policy = AxObserverRetryPolicy(shortRetryLimit: 2, initialRetryDelay: 10,
                                               maximumRetryDelay: 20, initialSparseDelay: 25,
                                               sparseCooldown: 100)

    private func time(_ rawValue: UInt64) -> MonotonicTimestamp { MonotonicTimestamp(rawValue: rawValue) }

    private func state(_ processes: [ProcessGeneration] = []) -> AxObserverHealthState {
        var state = AxObserverHealthState()
        for process in processes { _ = AxObserverHealth.reduce(
            &state,
            .processStarted(process),
            policy: policy
        ) }
        return state
    }

    private func begin(_ state: inout AxObserverHealthState, _ process: ProcessGeneration,
                       _ capability: AxNotificationCapability = .focusedWindowChanged) -> UInt64 {
        guard case let .subscriptionStarted(_, generation) = AxObserverHealth.reduce(
            &state, .beginSubscription(process, capability), policy: policy
        ) else { return 0 }
        return generation
    }

    private func complete(_ state: inout AxObserverHealthState, _ process: ProcessGeneration,
                          _ generation: UInt64, _ capability: AxNotificationCapability,
                          _ result: AxSubscriptionResult, _ at: UInt64 = 0) -> AxObserverHealthDecision {
        AxObserverHealth.reduce(
            &state,
            .subscriptionResult(process, observerGeneration: generation, capability,
                                result, at: time(at)),
            policy: policy
        )
    }

    func testObserverCreationFailureHasABoundedRecoverableStage() {
        var state = state([process])
        guard case let .observerCreationStarted(generation) = AxObserverHealth.reduce(&state,
            .beginObserverCreation(process, at: time(0)), policy: policy) else {
            return XCTFail("creation did not start")
        }
        XCTAssertEqual(AxObserverHealth.reduce(&state, .observerCreationResult(process,
            observerGeneration: generation, error: .genericFailure, at: time(0)), policy: policy),
            .observerCreationRetry(at: time(25)))
        XCTAssertEqual(AxObserverHealth.reduce(&state, .beginObserverCreation(process, at: time(24)),
            policy: policy), .ignored(.cooldown))
        guard case let .observerCreationStarted(retryGeneration) = AxObserverHealth.reduce(&state,
            .beginObserverCreation(process, at: time(25)), policy: policy) else {
            return XCTFail("creation did not retry")
        }
        XCTAssertEqual(retryGeneration, generation + 1)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .observerCreationResult(process,
            observerGeneration: retryGeneration, error: nil, at: time(26)), policy: policy),
            .observerReady(observerGeneration: retryGeneration))
        XCTAssertEqual(state.entry(for: process)?.observer, .ready)
    }

    func testSuccessfulObserverCreationResetsFailureBackoff() {
        var state = state([process])
        guard case let .observerCreationStarted(first) = AxObserverHealth.reduce(&state,
            .beginObserverCreation(process, at: time(0)), policy: policy) else {
            return XCTFail("creation did not start")
        }
        _ = AxObserverHealth.reduce(&state, .observerCreationResult(process,
            observerGeneration: first, error: .genericFailure, at: time(0)), policy: policy)
        guard case let .observerCreationStarted(second) = AxObserverHealth.reduce(&state,
            .beginObserverCreation(process, at: time(25)), policy: policy) else {
            return XCTFail("creation did not retry")
        }
        _ = AxObserverHealth.reduce(&state, .observerCreationResult(process,
            observerGeneration: second, error: nil, at: time(26)), policy: policy)
        guard case let .subscriptionStarted(_, generation) = AxObserverHealth.reduce(&state,
            .beginSubscription(process, .titleChanged)) else { return XCTFail("subscription did not start") }
        guard case let .observerRebuildRequired(_, replacement) = AxObserverHealth.reduce(&state,
            .subscriptionResult(process, observerGeneration: generation, .titleChanged,
                .invalidObserver, at: time(27)), policy: policy) else {
            return XCTFail("observer rebuild did not start")
        }
        XCTAssertEqual(AxObserverHealth.reduce(&state, .observerCreationResult(process,
            observerGeneration: replacement, error: .genericFailure, at: time(30)), policy: policy),
            .observerCreationRetry(at: time(55)))
    }

    func testSuccessAndAlreadyRegisteredSubscribeTheirCapability() {
        for result in [AxSubscriptionResult.success, .alreadyRegistered] {
            var state = state([process])
            let generation = begin(&state, process)
            XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, result, 7),
                           .capabilitySubscribed(.focusedWindowChanged))
            XCTAssertEqual(state.entry(for: process)?.capabilities, [.focusedWindowChanged])
            XCTAssertEqual(state.entry(for: process)?.lifecycle, .healthy)
        }
    }

    func testUnsupportedAndNotImplementedAreIndependent() {
        for result in [AxSubscriptionResult.notificationUnsupported, .notImplemented] {
            var state = state([process])
            var generation = begin(&state, process, .focusedWindowChanged)
            _ = complete(&state, process, generation, .focusedWindowChanged, .success)
            generation = begin(&state, process, .mainWindowChanged)
            XCTAssertEqual(complete(&state, process, generation, .mainWindowChanged, result),
                           .capabilityUnsupported(.mainWindowChanged))
            XCTAssertEqual(state.entry(for: process)?.notifications[.focusedWindowChanged], .subscribed)
            XCTAssertEqual(state.entry(for: process)?.notifications[.mainWindowChanged], .unsupported)
            XCTAssertEqual(state.entry(for: process)?.lifecycle, .healthy)
        }
    }

    func testCannotCompleteUsesShortExponentialBudgetThenSparseCooldown() {
        var state = state([process])
        var generation = begin(&state, process)
        XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 0),
                       .retryScheduled(.focusedWindowChanged, at: time(10), sparse: false))
        XCTAssertEqual(state.entry(for: process)?.lifecycle, .unresponsive)
        _ = AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(10)), policy: policy)
        generation = begin(&state, process)
        XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 10),
                       .retryScheduled(.focusedWindowChanged, at: time(30), sparse: false))
        _ = AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(30)), policy: policy)
        generation = begin(&state, process)
        XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 30),
                       .retryScheduled(.focusedWindowChanged, at: time(55), sparse: true))
        XCTAssertEqual(state.entry(for: process)?.diagnostics.nextRetry, time(55))
    }

    /// The sparse tier doubles up to the cooldown and stays there, so an app that starts answering again is
    /// asked within seconds instead of waiting out a flat cooldown.
    func testSparseCooldownGrowsToTheCapAndStaysThere() {
        var state = state([process])
        var at: UInt64 = 0
        for expected in [10, 30, 55, 105, 205, 305] {
            let generation = begin(&state, process)
            XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, at),
                           .retryScheduled(.focusedWindowChanged, at: time(UInt64(expected)),
                                           sparse: expected >= 55))
            at = UInt64(expected)
            _ = AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(at)), policy: policy)
        }
    }

    func testCannotCompleteBudgetIsIndependentPerCapability() {
        var state = state([process])
        var generation = begin(&state, process, .focusedWindowChanged)
        _ = complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 0)
        _ = AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(10)), policy: policy)
        generation = begin(&state, process, .focusedWindowChanged)
        _ = complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 10)
        generation = begin(&state, process, .mainWindowChanged)
        XCTAssertEqual(complete(&state, process, generation, .mainWindowChanged, .cannotComplete, 10),
                       .retryScheduled(.mainWindowChanged, at: time(20), sparse: false))
        XCTAssertEqual(state.entry(for: process)?.diagnostics.capabilityConsecutiveCannotComplete,
                       [.focusedWindowChanged: 2, .mainWindowChanged: 1])
        XCTAssertEqual(state.entry(for: process)?.diagnostics.consecutiveCannotComplete, 2)
        XCTAssertEqual(state.entry(for: process)?.diagnostics.capabilityAttemptCounts,
                       [.focusedWindowChanged: 2, .mainWindowChanged: 1])
        XCTAssertEqual(state.entry(for: process)?.diagnostics.attemptCount, 3)
    }

    func testSuccessAndCallbackDoNotResetAnotherCapabilityBudget() {
        var state = state([process])
        var generation = begin(&state, process, .focusedWindowChanged)
        _ = complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 0)
        _ = AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(10)), policy: policy)
        generation = begin(&state, process, .mainWindowChanged)
        _ = complete(&state, process, generation, .mainWindowChanged, .success, 10)
        _ = AxObserverHealth.reduce(&state, .callback(process, observerGeneration: generation,
                                                      .mainWindowChanged, at: time(11)), policy: policy)
        generation = begin(&state, process, .focusedWindowChanged)
        XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 11),
                       .retryScheduled(.focusedWindowChanged, at: time(31), sparse: false))
        XCTAssertEqual(state.entry(for: process)?.diagnostics.capabilityConsecutiveCannotComplete,
                       [.focusedWindowChanged: 2])
    }

    func testCooldownDoesNotBecomeHealthyAndCanRetryIndefinitely() {
        var state = state([process])
        let generation = begin(&state, process)
        _ = complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 0)
        XCTAssertEqual(
            AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(9)), policy: policy),
            .ignored(.cooldown)
        )
        XCTAssertEqual(state.entry(for: process)?.lifecycle, .unresponsive)
        XCTAssertEqual(
            AxObserverHealth.reduce(&state, .cooldownElapsed(process, at: time(10)), policy: policy),
            .recoveryStarted(.recoveryTick)
        )
        XCTAssertEqual(state.entry(for: process)?.lifecycle, .recovering)
        XCTAssertEqual(state.entry(for: process)?.notifications[.focusedWindowChanged], .unattempted)
    }

    func testEveryBoundedRecoveryTriggerTransitionsWhenPermitted() {
        let triggers: [AxRecoveryTrigger] = [.processBecameFrontmost, .wake, .unlock, .recoveryTick]
        for trigger in triggers {
            var state = state([process])
            let generation = begin(&state, process)
            _ = complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 0)
            XCTAssertEqual(AxObserverHealth.reduce(&state, .recoveryTriggered(process, trigger, at: time(10)),
                                                   policy: policy), .recoveryStarted(trigger))
            XCTAssertEqual(state.entry(for: process)?.lifecycle, .recovering)
        }
    }

    func testSuccessfulAxCallBypassesCooldownWithoutResettingCapabilityBudget() {
        var state = state([process])
        let generation = begin(&state, process)
        _ = complete(&state, process, generation, .focusedWindowChanged, .cannotComplete, 0)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .recoveryTriggered(process, .otherAxCallSucceeded,
                                                                          at: time(1)), policy: policy),
                       .recoveryStarted(.otherAxCallSucceeded))
        XCTAssertEqual(state.entry(for: process)?.diagnostics.capabilityConsecutiveCannotComplete,
                       [.focusedWindowChanged: 1])
    }

    func testInvalidElementAndObserverRebuildAndRejectOldGeneration() {
        for result in [AxSubscriptionResult.invalidUIElement, .invalidObserver] {
            var state = state([process])
            let generation = begin(&state, process)
            XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, result),
                           .observerRebuildRequired(cancelledGeneration: 1, replacementGeneration: 2))
            XCTAssertEqual(state.entry(for: process)?.lifecycle, .recovering)
            XCTAssertEqual(state.entry(for: process)?.notifications[.focusedWindowChanged], .unattempted)
            XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .success),
                           .ignored(.staleObserverGeneration))
        }
    }

    func testInvalidArgumentAndGenericFailureUseSparseDegradedCooldown() {
        for result in [AxSubscriptionResult.invalidArgument, .genericFailure] {
            var state = state([process])
            let generation = begin(&state, process)
            XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, result, 5),
                           .retryScheduled(.focusedWindowChanged, at: time(105), sparse: true))
            XCTAssertEqual(state.entry(for: process)?.lifecycle, .degraded)
        }
    }

    func testApiDisabledGatesEveryPidUntilGlobalRecovery() {
        var state = state([process, other])
        let generation = begin(&state, process)
        XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .apiDisabled),
                       .globalPermissionFailed)
        XCTAssertTrue(state.hasGlobalPermissionFailure)
        XCTAssertEqual(state.entry(for: other)?.lifecycle, .globalPermissionFailure)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .beginSubscription(other, .mainWindowChanged),
                                               policy: policy), .ignored(.globalPermissionFailure))
        XCTAssertEqual(
            AxObserverHealth.reduce(&state, .globalPermissionRestored(at: time(20)), policy: policy),
            .globalRecoveryStarted([process, other])
        )
        XCTAssertFalse(state.hasGlobalPermissionFailure)
        XCTAssertEqual(state.entry(for: process)?.observer, .absent)
        XCTAssertEqual(AxObserverHealth.reduce(&state,
            .beginObserverCreation(process, at: time(20)), policy: policy),
            .observerCreationStarted(observerGeneration: 2))
        XCTAssertEqual(state.entry(for: other)?.lifecycle, .recovering)
    }

    func testProcessStartedDuringGlobalPermissionFailureJoinsGateAndRecovers() {
        var state = state([process])
        let generation = begin(&state, process)
        _ = complete(&state, process, generation, .focusedWindowChanged, .apiDisabled)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .processStarted(other), policy: policy),
                       .processRegistered(other))
        XCTAssertEqual(state.entry(for: other)?.lifecycle, .globalPermissionFailure)
        XCTAssertEqual(state.entry(for: other)?.diagnostics.lastError, .apiDisabled)
        XCTAssertEqual(
            AxObserverHealth.reduce(&state, .globalPermissionRestored(at: time(20)), policy: policy),
            .globalRecoveryStarted([process, other])
        )
        XCTAssertEqual(state.entry(for: other)?.lifecycle, .recovering)
        XCTAssertEqual(begin(&state, other), 1)
    }

    func testProcessReplacementDuringGlobalPermissionFailureJoinsGateAndRecovers() {
        var state = state([process])
        let generation = begin(&state, process)
        _ = complete(&state, process, generation, .focusedWindowChanged, .apiDisabled)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .processStarted(replacement), policy: policy),
                       .processGenerationReplaced(process, cancelledObserverGeneration: generation))
        XCTAssertEqual(state.entry(for: replacement)?.lifecycle, .globalPermissionFailure)
        XCTAssertEqual(state.entry(for: replacement)?.diagnostics.lastError, .apiDisabled)
        _ = AxObserverHealth.reduce(&state, .globalPermissionRestored(at: time(20)), policy: policy)
        XCTAssertEqual(state.entry(for: replacement)?.lifecycle, .recovering)
        XCTAssertEqual(begin(&state, replacement), 1)
    }

    func testCallbackRecordsLivenessWithoutRepairingOtherCapability() {
        var state = state([process])
        var generation = begin(&state, process, .focusedWindowChanged)
        _ = complete(&state, process, generation, .focusedWindowChanged, .success)
        generation = begin(&state, process, .mainWindowChanged)
        _ = complete(&state, process, generation, .mainWindowChanged, .genericFailure)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .callback(process, observerGeneration: generation,
                                                                 .focusedWindowChanged, at: time(9)),
                                               policy: policy),
                       .callbackAccepted(.focusedWindowChanged))
        XCTAssertEqual(state.entry(for: process)?.lifecycle, .degraded)
        XCTAssertEqual(state.entry(for: process)?.notifications[.mainWindowChanged], .cooldown(until: time(100)))
    }

    func testPidGenerationReplacementKeepsOneFreshObserverState() {
        var state = state([process])
        _ = begin(&state, process)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .processStarted(replacement), policy: policy),
                       .processGenerationReplaced(process, cancelledObserverGeneration: 1))
        XCTAssertEqual(state.entries.count, 1)
        XCTAssertNil(state.entry(for: process))
        XCTAssertEqual(state.entry(for: replacement)?.diagnostics, AxObserverDiagnostics())
        XCTAssertEqual(complete(&state, process, 1, .focusedWindowChanged, .success),
                       .ignored(.staleProcessGeneration))
    }

    func testTeardownCancelsGenerationAndLateWorkCannotReachPidReuse() {
        var state = state([process])
        let generation = begin(&state, process)
        XCTAssertEqual(AxObserverHealth.reduce(&state, .teardown(process), policy: policy),
                       .tornDown(cancelledObserverGeneration: generation))
        XCTAssertTrue(state.entries.isEmpty)
        XCTAssertEqual(complete(&state, process, generation, .focusedWindowChanged, .success),
                       .ignored(.unknownProcess))
        _ = AxObserverHealth.reduce(&state, .processStarted(replacement), policy: policy)
        XCTAssertEqual(state.entry(for: replacement)?.diagnostics.observerGeneration, 0)
        XCTAssertEqual(
            state.entry(for: replacement)?.notifications.values.filter { $0 == .unattempted }.count,
            AxNotificationCapability.allCases.count
        )
    }

    /// **The subscription surface stays narrow.** Broad AX subscriptions are what harmed JetBrains-derived
    /// apps, LibreOffice and MATLAB, so the set this provider DEPENDS on is enumerated here and anything
    /// else has to be optional and off by default. A new capability that is neither fails here, which is
    /// the point.
    ///
    /// Three have been added deliberately, and every one of them REPLACES work the app was already doing
    /// rather than widening the surface. `titleChanged` replaces AX reads made against every app on every
    /// order event. `elementDestroyed` is the only prompt signal for a close while minimized, app-hidden, on
    /// another Space or as a background tab, and its matching order-out consumes the one duplicate probe.
    /// `windowCreated` carries a live element and its tab group while WindowServer remains the primary
    /// physical discovery trigger. All three are window-level notifications, not element-level streams.
    /// `focusedUIElementChanged` is the one that must never appear here.
    func testCapabilitySurfaceHasOnlyNarrowCoreNotifications() {
        let core = Set(AxNotificationCapability.allCases.filter { $0.isEnabled })
        XCTAssertEqual(core, [.focusedWindowChanged, .mainWindowChanged, .titleChanged,
                              .windowCreated, .elementDestroyed],
                       "a capability was added to the set every app gets subscribed to")
        XCTAssertFalse(AxNotificationCapability.focusedTabProbeEnabled,
                       "the focused-tab probe is a measurement and must stay off by default")
    }


    // MARK: the optional focused-tab probe

    /// **An app refusing an optional notification is not an unhealthy app.** The probe registers a private
    /// notification on every process; most will not support it, and treating that as a provider failure would
    /// quarantine half the machine over a measurement nothing depends on.
    func testUnsupportedOptionalCapabilityLeavesTheProviderHealthy() {
        var s = state([process])
        for capability in [AxNotificationCapability.focusedWindowChanged, .mainWindowChanged] {
            _ = AxObserverHealth.reduce(&s, .beginSubscription(process, capability), policy: policy)
            _ = AxObserverHealth.reduce(&s, .subscriptionResult(process, observerGeneration: 1, capability,
                                                                .success, at: time(1)), policy: policy)
        }
        _ = AxObserverHealth.reduce(&s, .beginSubscription(process, .focusedTabChanged), policy: policy)
        _ = AxObserverHealth.reduce(&s, .subscriptionResult(process, observerGeneration: 1, .focusedTabChanged,
                                                            .notificationUnsupported, at: time(2)),
                                    policy: policy)
        XCTAssertEqual(s.entry(for: process)?.lifecycle, .healthy)
        XCTAssertEqual(s.entry(for: process)?.notifications[.focusedTabChanged], .unsupported)
        XCTAssertTrue(s.entry(for: process)!.capabilities.contains(.focusedWindowChanged))
    }

    func testDestroyDeliveryOnlySuppressesTheMatchingWindowsNextProbe() {
        var correlation = AxDestroyCorrelation()
        correlation.note(10, at: 1)
        XCTAssertTrue(correlation.shouldProbe(11, at: 1.1))
        XCTAssertFalse(correlation.shouldProbe(10, at: 1.2))
        XCTAssertTrue(correlation.shouldProbe(10, at: 1.3), "the correlation is single-use")
    }

    func testStaleDestroyDeliveryDoesNotSuppressAProbe() {
        var correlation = AxDestroyCorrelation()
        correlation.note(10, at: 1)
        XCTAssertTrue(correlation.shouldProbe(10, at: 1 + AxDestroyCorrelation.horizon + 0.001))
    }

    func testAxNodeReplacementAlwaysKeepsTheWindow() {
        XCTAssertEqual(AxElementEndPolicy.decide(ax: .foundReplacement, surfacePresent: false,
            isTabbed: false, groupShrank: false, axQueryCoversWindow: true), .replacementFound)
    }

    func testAxDestroyAndWindowServerAbsenceConfirmClose() {
        XCTAssertEqual(AxElementEndPolicy.decide(ax: .noAnswer, surfacePresent: false,
            isTabbed: true, groupShrank: false, axQueryCoversWindow: false), .confirmedClosed)
    }

    func testRetainedSurfaceDoesNotShieldSemanticClose() {
        XCTAssertEqual(AxElementEndPolicy.decide(ax: .absent, surfacePresent: true,
            isTabbed: false, groupShrank: false, axQueryCoversWindow: true), .confirmedClosed)
    }

    func testAmbiguousTabAndOutOfScopeAbsencesRemainPending() {
        XCTAssertEqual(AxElementEndPolicy.decide(ax: .absent, surfacePresent: true,
            isTabbed: true, groupShrank: false, axQueryCoversWindow: true), .inconclusive)
        XCTAssertEqual(AxElementEndPolicy.decide(ax: .absent, surfacePresent: true,
            isTabbed: false, groupShrank: false, axQueryCoversWindow: false), .inconclusive)
        XCTAssertEqual(AxElementEndPolicy.decide(ax: .absent, surfacePresent: true,
            isTabbed: true, groupShrank: true, axQueryCoversWindow: true), .confirmedClosed)
    }

}
