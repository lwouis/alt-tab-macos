import Cocoa
import XCTest

final class LateReminderTests: XCTestCase {
    private let suite = "com.lwouis.alt-tab-macos.tests.LateReminder"
    private var defaults: UserDefaults!
    private var experiment: LateReminderExperiment!
    private var context: LateReminderExperiment.Context!
    private var presentation: ProPromptPresentation!
    private var presenter: LateReminderPopover!
    private var popovers = [LateTestPopover]()
    private var checkouts = [CheckoutOrigin]()
    private var allowed = true
    private var readiness = StatusItemAnchor.Readiness.ready
    private let anchor = NSView()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        defaults = TestDefaults.make(suite)
        experiment = LateReminderExperiment(defaults: defaults, fingerprint: { "machine-1" })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        context = .init(now: now, trialStart: now.addingTimeInterval(-63 * 86400), isFree: true,
                        optedOut: false, lastMessage: nil, calendar: calendar)
        presentation = ProPromptPresentation()
    }

    override func tearDown() {
        presentation.cancel()
        popovers.forEach { $0.close() }
        presenter = nil
        TestDefaults.tearDown(defaults, suite)
        TestDefaults.tearDown(ProTransitionState.defaults, ProTransitionState.suite)
        super.tearDown()
    }

    func test63CompleteDaysIncludeOldInstallsWithoutAnActivationDate() {
        for days in [62.0, 63.0 - 1 / 86400, 63.0, 500.0] {
            context.trialStart = context.now.addingTimeInterval(-days * 86400)
            XCTAssertEqual(context.inPopulation, days >= 63)
        }
    }

    func testMissingTrialFreeStateAndPermanentRefusal() {
        experiment.recordActivity(context)
        XCTAssertTrue(experiment.canOffer(context))
        context.trialStart = nil
        XCTAssertFalse(experiment.canOffer(context))
        context.trialStart = context.now.addingTimeInterval(-100 * 86400)
        context.isFree = false
        XCTAssertFalse(experiment.canOffer(context))
        XCTAssertFalse(experiment.canAttribute(context))
        context.isFree = true
        context.optedOut = true
        XCTAssertFalse(experiment.canOffer(context))
        XCTAssertFalse(experiment.canAttribute(context))
    }

    func testUseTodayAndSevenFullDaysWithoutAnyProMessage() {
        XCTAssertFalse(experiment.canOffer(context))
        XCTAssertFalse(experiment.canAttribute(context))
        experiment.recordActivity(context)
        XCTAssertTrue(experiment.canOffer(context))
        for age in [7 * 86400, 7 * 86400 - 1, 0, -1] {
            context.lastMessage = context.now.addingTimeInterval(-Double(age))
            XCTAssertEqual(experiment.canOffer(context), age >= 7 * 86400)
            XCTAssertEqual(experiment.canAttribute(context), age >= 7 * 86400)
        }
        context.lastMessage = nil
        context.now.addTimeInterval(86400)
        XCTAssertFalse(experiment.canOffer(context))
        experiment.recordActivity(context)
        XCTAssertTrue(experiment.canOffer(context))
    }

    func testEligibleActivityAllowsEveryHourAndTimeZone() {
        let start = context.now
        context.trialStart = start.addingTimeInterval(-100 * 86400)
        for offset in [-12, 0, 9, 14] {
            context.calendar.timeZone = TimeZone(secondsFromGMT: offset * 3600)!
            for hour in 0 ..< 24 {
                context.now = start.addingTimeInterval(Double(hour) * 3600)
                experiment.recordActivity(context)
                XCTAssertTrue(experiment.canOffer(context))
            }
        }
    }

    func testExpiredTrialHasNoScheduledReminderEvenWithAnOldSavedDeadline() {
        let clock = MockClock(now: context.now)
        defaults.set(context.trialStart?.timeIntervalSince1970, forKey: "trialStartDate")
        let license = LicenseManager(clock: clock, keychain: MockKeychain(), api: MockLicenseAPI(), defaults: defaults)
        license.initialize()
        experiment.recordActivity(context)
        defaults.set(context.now.addingTimeInterval(-1).timeIntervalSince1970, forKey: "proTransition.nextScheduledDate")
        let scheduler = ProTransitionScheduler(defaults: defaults, licenseManager: license,
            state: ProTransitionState(), onFire: {})
        scheduler.onAppLaunchComplete()
        XCTAssertNil(scheduler.computeNextFireDate())
        XCTAssertNil(defaults.object(forKey: "proTransition.nextScheduledDate"))
        scheduler.cancel()
    }

    #if DEBUG
    func testQaClockJumpRearmsTheExistingBadgeDeadline() {
        let clock = MockClock(now: context.now)
        let start = clock.now.addingTimeInterval(-11 * 86400)
        let badgeDate = start.addingTimeInterval(12 * 86400 + 1)
        defaults.set(start.timeIntervalSince1970, forKey: "trialStartDate")
        let license = LicenseManager(clock: clock, keychain: MockKeychain(), api: MockLicenseAPI(), defaults: defaults)
        license.initialize()
        let state = ProTransitionState()
        state.hasSeenWelcome = true
        let fired = expectation(description: "badge deadline after the QA clock jump")
        let scheduler = ProTransitionScheduler(defaults: defaults, licenseManager: license, state: state, onFire: {
            clock.now = badgeDate
            fired.fulfill()
        })
        defer { scheduler.cancel() }
        scheduler.onAppLaunchComplete()
        XCTAssertEqual(scheduler.computeNextFireDate(), badgeDate)
        clock.now = badgeDate.addingTimeInterval(-0.05)
        scheduler.invalidateTimerForQa()
        XCTAssertEqual(defaults.double(forKey: "proTransition.nextScheduledDate"), badgeDate.timeIntervalSince1970)
        scheduler.onAppLaunchComplete()
        wait(for: [fired], timeout: 1)
    }
    #endif

    func testCoordinatorQueuesOnlyAfterAWindowIsSelected() {
        let manager = makeManager()
        let shown = expectation(description: "late reminder after selecting a window")
        manager.onAction = { if case .showLateReminder = $0 { shown.fulfill() } }
        manager.onSwitcherShown()
        XCTAssertFalse(manager.hasPendingPrompt)
        manager.onSwitcherDismissed()
        XCTAssertFalse(manager.hasPendingPrompt)
        manager.onSwitcherShown()
        manager.onSwitcherDismissed(didSwitchWindow: true)
        XCTAssertTrue(manager.hasPendingPrompt)
        wait(for: [shown], timeout: 3)
        XCTAssertFalse(manager.hasPendingPrompt)
        manager.userOptedOut = true
        manager.onSwitcherShown()
        manager.onSwitcherDismissed(didSwitchWindow: true)
        XCTAssertFalse(manager.hasPendingPrompt)
        XCTAssertTrue(manager.state.intents.isEmpty)
    }

    func testUpdateOffersOnceAfterReadinessWithoutWaitingForSwitching() {
        let manager = makeManager()
        var reminders = 0
        manager.onAction = { if case .showLateReminder = $0 { reminders += 1 } }
        XCTAssertFalse(manager.lateReminder.canOffer(manager.lateReminderContext()))
        manager.onAppLaunchComplete(didUpdate: true)
        XCTAssertEqual(reminders, 0)
        XCTAssertTrue(manager.lateReminder.canOffer(manager.lateReminderContext()))
        drain()
        XCTAssertEqual(reminders, 1)
        manager.onAppLaunchComplete(didUpdate: true)
        drain()
        XCTAssertEqual(reminders, 1)
    }

    func testOrdinaryLaunchAndOutlivedDeadlineCannotOfferTheReminder() {
        let manager = makeManager()
        manager.lateReminder.recordActivity(manager.lateReminderContext())
        ProTransitionState.defaults.set(context.now.addingTimeInterval(-1).timeIntervalSince1970,
            forKey: "proTransition.nextScheduledDate")
        manager.onAction = { if case .showLateReminder = $0 { XCTFail("Only an update or window selection may offer") } }
        manager.onAppLaunchComplete()
        drain()
        XCTAssertFalse(manager.hasPendingPrompt)
    }

    func testUpdateRechecksRefusalAndCancellationBeforeShowing() {
        let manager = makeManager()
        manager.onAction = { if case .showLateReminder = $0 { XCTFail("Cancelled update prompt") } }
        manager.onAppLaunchComplete(didUpdate: true)
        XCTAssertTrue(manager.hasPendingPrompt)
        manager.userOptedOut = true
        drain()
        XCTAssertFalse(manager.hasPendingPrompt)
        XCTAssertNil(ProTransitionState.defaults.object(forKey: "lateReminder.opportunityAt"))
    }

    func testUpdateBeforeDay63WaitsForALaterWindowSelection() {
        context.trialStart = context.now.addingTimeInterval(-62 * 86400)
        let clock = MockClock(now: context.now)
        let manager = makeManager(clock: clock)
        let shown = expectation(description: "late reminder after reaching 63 days")
        manager.onAction = { if case .showLateReminder = $0 { shown.fulfill() } }
        manager.onAppLaunchComplete(didUpdate: true)
        XCTAssertFalse(manager.hasPendingPrompt)
        clock.now.addTimeInterval(86400)
        manager.onSwitcherShown()
        manager.onSwitcherDismissed(didSwitchWindow: true)
        XCTAssertTrue(manager.hasPendingPrompt)
        wait(for: [shown], timeout: 3)
        XCTAssertFalse(manager.hasPendingPrompt)
    }

    private func makeManager(clock: MockClock? = nil) -> ProTransitionManager {
        _ = TestDefaults.make(ProTransitionState.suite)
        defaults.set(context.trialStart?.timeIntervalSince1970, forKey: "trialStartDate")
        let license = LicenseManager(clock: clock ?? MockClock(now: context.now), keychain: MockKeychain(),
                                     api: MockLicenseAPI(), defaults: defaults)
        license.initialize()
        XCTAssertEqual(license.trialStartDate, context.trialStart)
        let manager = ProTransitionManager(licenseManager: { license }, canPresentProactively: { self.allowed })
        manager.state.value.isTrialActive = false
        manager.state.value.daysSinceTrialStart = 63
        manager.state.freePassUsed = true
        manager.state.hasSeenFullUpgrade = true
        return manager
    }

    func testSaltedFirstBitVectorsAndAssignmentSurviveReplacement() {
        XCTAssertEqual(LateReminderExperiment.assign("machine-0"), .control)
        XCTAssertEqual(LateReminderExperiment.assign("machine-1"), .treatment)
        XCTAssertEqual(LateReminderExperiment.assign("machine-2"), .control)
        let done = expectation(description: "local assignment persisted")
        experiment.loadArm { [self] arm in
            XCTAssertEqual(arm, .treatment)
            let replacement = LateReminderExperiment(defaults: defaults, fingerprint: {
                XCTFail("An existing arm must never be redrawn")
                return "machine-0"
            })
            replacement.loadArm { XCTAssertEqual($0, .treatment); done.fulfill() }
        }
        wait(for: [done], timeout: 3)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "machine-1" })
    }

    func testControlIsSilentAndConsumedForeverWithoutRecordingAMessage() {
        prepare(.control)
        let messages = ProTransitionManager.shared.state.messages
        presenter.show()
        XCTAssertTrue(popovers.isEmpty)
        XCTAssertEqual(ProTransitionManager.shared.state.messages, messages)
        XCTAssertNotNil(defaults.object(forKey: "lateReminder.opportunityAt"))
        context.now.addTimeInterval(400 * 86400)
        experiment.recordActivity(context)
        let replacement = LateReminderExperiment(defaults: defaults)
        XCTAssertFalse(replacement.canOffer(context))
        XCTAssertTrue(replacement.canAttribute(context))
    }

    func testTreatmentAcknowledgesVisiblePresentationAndNotNowHasNoFollowUp() throws {
        prepare(.treatment)
        presenter.show()
        XCTAssertNil(defaults.object(forKey: "lateReminder.opportunityAt"))
        drain()
        let popover = try XCTUnwrap(popovers.first)
        XCTAssertTrue(popover.isShown)
        XCTAssertFalse(popover.takesKeyboardFocus)
        XCTAssertNotNil(defaults.object(forKey: "lateReminder.opportunityAt"))
        try button("Not now", in: popover).performClick(nil)
        XCTAssertFalse(popover.isShown)
        XCTAssertFalse(context.optedOut)
        XCTAssertTrue(checkouts.isEmpty)
        presenter.show()
        XCTAssertEqual(popovers.count, 1)
    }

    func testGetProUsesA9AndRefusalUsesTheSharedOptOut() throws {
        for refuse in [false, true] {
            defaults.removeObject(forKey: "lateReminder.opportunityAt")
            prepare(.treatment)
            presenter.show()
            drain()
            let popover = try XCTUnwrap(popovers.last)
            try button(refuse ? "Don't mention again" : "Get Pro", in: popover).performClick(nil)
            XCTAssertFalse(popover.isShown)
            XCTAssertEqual(context.optedOut, refuse)
        }
        XCTAssertEqual(checkouts, [.lateReminder])
    }

    func testOutsideClicksDismissTheReminderWithAnAvailableOrHiddenMenuIcon() throws {
        for anchor in [StatusItemAnchor.Readiness.ready, .unavailable] {
            for global in [false, true] {
                defaults.removeObject(forKey: "lateReminder.opportunityAt")
                readiness = anchor
                prepare(.treatment)
                presenter.show()
                drain()
                let popover = try XCTUnwrap(popovers.last)
                XCTAssertTrue(popover.isShown)
                let opportunity = try XCTUnwrap(defaults.object(forKey: "lateReminder.opportunityAt") as? Date)
                let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
                popover.handleDismissalEvent(click, isGlobal: global)
                XCTAssertFalse(popover.isShown)
                XCTAssertNil(popover.contentViewController)
                XCTAssertEqual(defaults.object(forKey: "lateReminder.opportunityAt") as? Date, opportunity)
                XCTAssertFalse(context.optedOut)
                XCTAssertTrue(checkouts.isEmpty)
                let count = popovers.count
                presenter.show()
                XCTAssertEqual(popovers.count, count)
                popover.close()
            }
        }
    }

    func testAnchorRechecksRefusalCooldownAndCompetingUIWithoutConsuming() throws {
        for condition in 0 ..< 3 {
            context.optedOut = false
            context.lastMessage = nil
            allowed = true
            readiness = .settling
            prepare(.treatment)
            presenter.show()
            drain()
            let popover = try XCTUnwrap(popovers.last)
            XCTAssertTrue(popover.isWaitingForAnchor)
            if condition == 0 { context.optedOut = true }
            if condition == 1 { context.lastMessage = context.now }
            if condition == 2 { allowed = false }
            popover.ready = .ready
            popover.retryPresentation()
            drain()
            XCTAssertFalse(popover.isShown)
            XCTAssertNil(defaults.object(forKey: "lateReminder.opportunityAt"))
        }
    }

    func testCancelledOrLateHistoryCannotShowOrConsumeEitherArm() {
        for arm in [LateReminderExperiment.Arm.treatment, .control] {
            var complete: ((LateReminderExperiment.Usage) -> Void)?
            prepare(arm, load: { _, _, callback in complete = callback })
            presenter.show()
            XCTAssertTrue(presentation.isPending)
            presentation.cancel()
            complete?(.init(months: 2, count: 42))
            XCTAssertTrue(popovers.isEmpty)
            XCTAssertNil(defaults.object(forKey: "lateReminder.opportunityAt"))
        }
    }

    func testEveryCheckoutOriginHasOnlyViaAndAnEligibleArmIncludingAfterTheReminder() {
        for arm in [LateReminderExperiment.Arm.treatment, .control] {
            prepare(arm)
            experiment.checkoutArm(context: { self.context }) { value in
                XCTAssertEqual(value, arm)
                for origin in CheckoutOrigin.allCases {
                    let url = Endpoints.checkoutUrl(from: origin, trialDay: 64, arm: value, website: "https://alt-tab.app")
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
                    XCTAssertEqual(query, [.init(name: "via", value: "64-" + origin.rawValue),
                                           .init(name: "arm", value: arm.rawValue)])
                }
            }
            experiment.consume(at: context.now)
            context.lastMessage = context.now
            XCTAssertTrue(experiment.canAttribute(context))
            context.lastMessage = nil
        }
        XCTAssertEqual(CheckoutOrigin.lateReminder.rawValue, "a9")
    }

    func testNoArmOutsideEligibilityAndNoFingerprintRead() {
        experiment = LateReminderExperiment(defaults: defaults, fingerprint: {
            XCTFail("Ineligible checkout must not read the fingerprint")
            return ""
        }, scheduleCheckoutTimeout: { _ in XCTFail("Ineligible checkout must finish immediately") })
        let eligible = context!
        for reason in 0 ..< 6 {
            context = eligible
            if reason != 0 { experiment.recordActivity(context) }
            if reason == 1 { context.trialStart = nil }
            if reason == 2 { context.trialStart = context.now.addingTimeInterval(-62 * 86400) }
            if reason == 3 { context.optedOut = true }
            if reason == 4 { context.isFree = false }
            if reason == 5 { context.lastMessage = context.now }
            experiment.checkoutArm(context: { self.context }) { arm in
                XCTAssertNil(arm)
                XCTAssertEqual(Endpoints.checkoutUrl(from: .menubar, trialDay: 63, arm: arm,
                    website: "https://alt-tab.app").absoluteString, "https://alt-tab.app/pricing?via=63-a8")
            }
        }
    }

    func testCheckoutTimeoutOpensOnceWithoutEnrollmentAndLateAssignmentOnlyCachesTheArm() {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        experiment = LateReminderExperiment(defaults: defaults, fingerprint: {
            gate.wait()
            return "machine-1"
        })
        experiment.recordActivity(context)
        let opened = expectation(description: "checkout opens despite a suspended fingerprint read")
        var results = [LateReminderExperiment.Arm?]()
        experiment.checkoutArm(context: { self.context }) { arm in
            results.append(arm)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 2)
        XCTAssertEqual(results, [nil])
        XCTAssertNil(defaults.object(forKey: "lateReminder.enrolledAt"))
        let loaded = expectation(description: "late assignment finishes")
        experiment.loadArm { _ in loaded.fulfill() }
        gate.signal()
        wait(for: [loaded], timeout: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(defaults.object(forKey: "lateReminder.enrolledAt"))
        XCTAssertNil(defaults.object(forKey: "lateReminder.opportunityAt"))
        XCTAssertEqual(defaults.string(forKey: "lateReminder.arm"), LateReminderExperiment.assign("machine-1").rawValue)
        experiment.checkoutArm(context: { self.context }) { results.append($0) }
        XCTAssertEqual(results, [nil, LateReminderExperiment.assign("machine-1")])
        XCTAssertEqual(defaults.object(forKey: "lateReminder.enrolledAt") as? Date, context.now)
    }

    func testCheckoutAssignmentCancelsItsDeadlineAndRechecksEligibility() throws {
        for optedOut in [false, true] {
            defaults.removeObject(forKey: "lateReminder.arm")
            defaults.removeObject(forKey: "lateReminder.enrolledAt")
            context.optedOut = false
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            var deadlines = [DispatchWorkItem]()
            experiment = LateReminderExperiment(defaults: defaults, fingerprint: {
                gate.wait()
                return "machine-1"
            }, scheduleCheckoutTimeout: { deadlines.append($0) })
            experiment.recordActivity(context)
            let opened = expectation(description: "assignment resolves checkout")
            var results = [LateReminderExperiment.Arm?]()
            experiment.checkoutArm(context: { self.context }) { arm in
                results.append(arm)
                opened.fulfill()
            }
            XCTAssertEqual(deadlines.count, 1)
            context.optedOut = optedOut
            gate.signal()
            wait(for: [opened], timeout: 1)
            let deadline = try XCTUnwrap(deadlines.first)
            XCTAssertTrue(deadline.isCancelled)
            deadline.perform()
            XCTAssertEqual(results, [optedOut ? nil : LateReminderExperiment.assign("machine-1")])
            XCTAssertEqual(defaults.object(forKey: "lateReminder.enrolledAt") as? Date, optedOut ? nil : context.now)
        }
    }

    func testConcurrentCheckoutsShareAssignmentButHaveIndependentDeadlines() throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let read = expectation(description: "one shared fingerprint read")
        var deadlines = [DispatchWorkItem]()
        experiment = LateReminderExperiment(defaults: defaults, fingerprint: {
            read.fulfill()
            gate.wait()
            return "machine-1"
        }, scheduleCheckoutTimeout: { deadlines.append($0) })
        experiment.recordActivity(context)
        var first = [LateReminderExperiment.Arm?]()
        var second = [LateReminderExperiment.Arm?]()
        experiment.checkoutArm(context: { self.context }) { first.append($0) }
        let opened = expectation(description: "second checkout receives assignment")
        experiment.checkoutArm(context: { self.context }) { arm in
            second.append(arm)
            opened.fulfill()
        }
        wait(for: [read], timeout: 1)
        XCTAssertEqual(deadlines.count, 2)
        try XCTUnwrap(deadlines.first).perform()
        XCTAssertEqual(first, [nil])
        XCTAssertTrue(second.isEmpty)
        XCTAssertNil(defaults.object(forKey: "lateReminder.enrolledAt"))
        gate.signal()
        wait(for: [opened], timeout: 1)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second, [LateReminderExperiment.assign("machine-1")])
    }

    func testCachedCheckoutDoesNotScheduleADeadlineOrReadTheFingerprint() {
        defaults.set("c", forKey: "lateReminder.arm")
        experiment = LateReminderExperiment(defaults: defaults, fingerprint: {
            XCTFail("Saved assignment must be reused")
            return ""
        }, scheduleCheckoutTimeout: { _ in XCTFail("Cached checkout must finish immediately") })
        experiment.recordActivity(context)
        var results = [LateReminderExperiment.Arm?]()
        experiment.checkoutArm(context: { self.context }) { results.append($0) }
        XCTAssertEqual(results, [.control])
    }

    func testMonthsRoundToNearestAndCountsUseTheAdvertisedPeriod() {
        typealias Usage = LateReminderExperiment.Usage
        for (days, months) in [(59, 2), (63, 2), (74, 2), (75, 3), (76, 3), (180, 6), (210, 7), (359, 12), (900, 12)] {
            XCTAssertEqual(Usage.months(since: context.now.addingTimeInterval(-Double(days) * 86400), now: context.now), months)
        }
        let end = Int(context.now.timeIntervalSince1970)
        let start = end - 60 * 86400
        XCTAssertEqual(Usage.count([start - 1, start, end, end + 1], months: 2, now: context.now), 2)
        XCTAssertNil(Usage.count(nil, months: 2, now: context.now))
        XCTAssertNil(Usage.count([-1], months: 2, now: context.now))
        XCTAssertTrue(LateReminderPopover.body(.init(months: 2, count: 42)).contains("42 times over the last 2 months"))
        XCTAssertFalse(LateReminderPopover.body(.init(months: 2, count: nil)).contains("times"))
    }

    private func prepare(_ arm: LateReminderExperiment.Arm,
                         load: @escaping (Int, Date, @escaping (LateReminderExperiment.Usage) -> Void) -> Void = {
                             months, _, complete in complete(.init(months: months, count: 42))
                         }) {
        defaults.set(arm.rawValue, forKey: "lateReminder.arm")
        experiment.recordActivity(context)
        presenter = LateReminderPopover(experiment: experiment, context: { self.context }, presentation: presentation,
            canPresent: { _ in self.allowed }, makePopover: {
                let popover = LateTestPopover(anchor: self.anchor)
                popover.ready = self.readiness
                self.popovers.append(popover)
                return ProPromptPopover.make(popover: popover)
            }, loadUsage: load, openCheckout: { self.checkouts.append($0) }, optOut: { self.context.optedOut = true })
    }

    private func button(_ title: String, in popover: AnchoredPopover) throws -> NSButton {
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        return try XCTUnwrap(buttons(try XCTUnwrap(popover.contentViewController?.view)).first { $0.title == title })
    }

    private func drain() {
        let done = expectation(description: "anchor layout")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}

private final class LateTestPopover: AnchoredPopover {
    private let anchor: NSView
    var ready = StatusItemAnchor.Readiness.ready
    private var displayed = false
    override var isShown: Bool { displayed }

    init(anchor: NSView) { self.anchor = anchor; super.init() }
    required init?(coder: NSCoder) { fatalError("Tests construct popovers directly") }

    override func present(_ content: NSView, from item: NSStatusItem?, canPresent: @escaping () -> Bool,
                          onShown: (() -> Void)?) {
        super.present(content, from: anchor, canPresent: canPresent, onShown: onShown)
    }

    override func readiness(of anchor: NSView, isHidden: Bool, deadlinePassed: Bool) -> StatusItemAnchor.Readiness { ready }

    override func showImmediately(from anchor: NSView) -> Bool {
        displayed = true
        NotificationCenter.default.post(name: NSPopover.didShowNotification, object: self)
        return true
    }

    override func showUnanchored() -> Bool { showImmediately(from: anchor) }
    override func close() { displayed = false; super.close() }
}
