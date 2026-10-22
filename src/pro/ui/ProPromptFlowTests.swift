import Cocoa
import XCTest

final class ProPromptFlowTests: XCTestCase {
    private var manager: ProTransitionManager!
    private var host: ProPromptHost!
    private var context = ProPromptPresentation.Context()
    private var popovers = [FlowPopover]()
    private var checkouts = [CheckoutOrigin]()
    private var readiness = StatusItemAnchor.Readiness.ready
    private var anchor = NSView()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        ProPromptPopover.closeAll()
        SwitcherSession.current = nil
        App.hideUiCount = 0
        Preferences.shortcutStyle = .focusOnRelease
        let license = LicenseManager(clock: MockClock(now: Date(timeIntervalSince1970: 1_700_000_000)),
                                     keychain: MockKeychain(), api: MockLicenseAPI(), defaults: ProTransitionState.defaults)
        manager = ProTransitionManager(licenseManager: { license })
        manager.state.value.isTrialActive = false
        manager.state.value.daysSinceTrialStart = 15
        manager.state.freePassUsed = true
        manager.state.hasSeenFullUpgrade = true
        manager.state.hasTriggeredPostExpirationSwitcher = true
        host = ProPromptHost(context: { [unowned self] _ in
            var value = context
            value.switcherActive = SwitcherSession.isActive
            return value
        }, makeHardGatePopover: { [unowned self] in
            let popover = FlowPopover(anchor: anchor)
            popover.readiness = readiness
            popovers.append(popover)
            return ProPromptPopover.make(popover: popover)
        }, openCheckout: { [unowned self] in checkouts.append($0) }, observeWorkspace: false)
        manager.onAction = { [unowned self] in host.dispatch($0) }
    }

    override func tearDown() {
        ProPromptPopover.closeAll()
        ProPromptHost.windowPresentation.cancel()
        manager.cancelPendingPrompts()
        SwitcherSession.current = nil
        ControlsTab.shortcuts.values.forEach { $0.state = .up }
        ControlsTab.shortcutsActionsTriggered = []
        ModifierFlags.current = []
        ModifierReleaseLog.reset()
        host = nil
        manager = nil
        popovers = []
        TestDefaults.tearDown(ProTransitionState.defaults, ProTransitionState.suite)
        super.tearDown()
    }

    func testBlockedSearchKeepsTheSessionAndSelectionAndPresentsBeforeDismissal() throws {
        summon()
        let session = try XCTUnwrap(SwitcherSession.current)
        session.selectedIndex = 3
        session.forceDoNothingOnRelease = false
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        XCTAssertTrue(SwitcherSession.current === session)
        XCTAssertEqual(session.selectedIndex, 3)
        XCTAssertFalse(session.forceDoNothingOnRelease)
        XCTAssertEqual(App.hideUiCount, 0)
        XCTAssertFalse(manager.hasPendingPrompt)
        drain()
        let popover = try XCTUnwrap(popovers.last)
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(popover.showCount, 1)
        XCTAssertEqual(popover.behavior, .applicationDefined)
        XCTAssertFalse(popover.takesKeyboardFocus)
        XCTAssertEqual(title(popover), ResolvedReason.search.unlockHeader)
        XCTAssertTrue(popover.contentViewController!.view.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
            .contains(ProFeatureCopy.purchaseTerms))
    }

    func testUnfinishedSetupDoesNotPresentAGateOrRecordPurchaseIntent() {
        manager.state.value.isAwaitingTrial = true
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        XCTAssertTrue(popovers.isEmpty)
        XCTAssertTrue(manager.state.intents.isEmpty)
        XCTAssertFalse(manager.hasPendingPrompt)
        XCTAssertEqual(App.hideUiCount, 0)
    }

    func testEscapeDismissesGateWithLocalOrGlobalKeyboardFocus() throws {
        for isGlobal in [false, true] {
            XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
            drain()
            let popover = try XCTUnwrap(popovers.last)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
            popover.handleDismissalEvent(event, isGlobal: isGlobal)
            XCTAssertFalse(popover.isShown)
            XCTAssertNil(popover.contentViewController)
            XCTAssertTrue(checkouts.isEmpty)
        }
    }

    func testEscapeDiscardedAfterSwitcherDismissalStillDismissesGate() throws {
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        let popover = try XCTUnwrap(popovers.last)
        DismissalInput.begin()
        defer { DismissalInput.cancel() }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        XCTAssertTrue(DismissalInput.discard(event))
        XCTAssertFalse(popover.isShown)
        XCTAssertTrue(checkouts.isEmpty)
    }

    func testEscapeInterceptedBySwitcherDismissesGateAndStillTriggersCancelShortcut() throws {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        ControlsTab.shortcuts.values.forEach { $0.state = .up }
        ModifierFlags.current = [.option]
        summon()
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        let popover = try XCTUnwrap(popovers.last)
        handleKeyboardEvent(nil, nil, 53, [.option], false)
        XCTAssertFalse(popover.isShown)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered.last, "cancelShortcut")
        XCTAssertTrue(checkouts.isEmpty)
    }

    func testOutsideClicksDismissGateInAltTabAndOtherApps() throws {
        for isGlobal in [false, true] {
            for type: NSEvent.EventType in [.leftMouseDown, .rightMouseDown, .otherMouseDown] {
                XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
                drain()
                let popover = try XCTUnwrap(popovers.last)
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
                popover.handleDismissalEvent(event, isGlobal: isGlobal)
                XCTAssertFalse(popover.isShown)
                XCTAssertNil(popover.contentViewController)
                XCTAssertTrue(checkouts.isEmpty)
            }
        }
    }

    func testInsideClicksAndOtherKeysLeaveGateAvailableForPurchase() throws {
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        let popover = try XCTUnwrap(popovers.last)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = popover.contentViewController?.view
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        popover.handleDismissalEvent(click)
        let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        popover.handleDismissalEvent(key)
        XCTAssertTrue(popover.isShown)
        XCTAssertTrue(checkouts.isEmpty)
        try getPro(popover).performClick(nil)
        XCTAssertFalse(popover.isShown)
        XCTAssertEqual(checkouts, [.hardGate])
    }

    func testCyclingAndModifierReleaseStillRouteAndGetProWorksAfterDismissal() throws {
        ControlsTab.shortcuts = ControlsTab.defaultShortcuts
        ControlsTab.shortcuts.values.forEach { $0.state = .up }
        ControlsTab.shortcutsActionsTriggered = []
        ModifierReleaseLog.reset()
        ModifierFlags.current = [.option]
        handleKeyboardEvent(nil, nil, nil, [.option], false)
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .down, nil, nil, false)
        handleKeyboardEvent(KeyboardEventsTestable.globalShortcutsIds["nextWindowShortcut"], .up, nil, nil, false)
        manager.onSwitcherShown()
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        let popover = try XCTUnwrap(popovers.last)
        handleKeyboardEvent(nil, nil, 124, [.option], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered.last, "→")
        ModifierFlags.current = []
        handleKeyboardEvent(nil, nil, nil, [], false)
        XCTAssertEqual(ControlsTab.shortcutsActionsTriggered.last, "holdShortcut")
        XCTAssertNil(SwitcherSession.current)
        manager.onSwitcherDismissed()
        drain()
        XCTAssertTrue(popover.isShown)
        XCTAssertFalse(manager.hasPendingPrompt)
        let button = try getPro(popover)
        XCTAssertEqual(button.keyEquivalent, "")
        for code: UInt16 in [36, 76] {
            button.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code)))
        }
        XCTAssertTrue(checkouts.isEmpty)
        button.performClick(nil)
        XCTAssertEqual(checkouts.count, 1)
        XCTAssertEqual(checkouts.first, .hardGate)
        XCTAssertFalse(popover.isShown)
        XCTAssertNil(popover.contentViewController)
    }

    func testRepeatedAttemptsReplacePendingAndVisibleContentWithoutDuplicates() throws {
        summon()
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        XCTAssertFalse(manager.attemptHardGatedFeature(.extraShortcut(index: 1)))
        drain()
        XCTAssertEqual(popovers[0].showCount, 0)
        XCTAssertNil(popovers[0].contentViewController)
        XCTAssertEqual(title(popovers[1]), ResolvedReason.extraShortcut.unlockHeader)
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        XCTAssertFalse(popovers[1].isShown)
        XCTAssertEqual(title(popovers[2]), ResolvedReason.search.unlockHeader)
        XCTAssertEqual(popovers.filter(\.isShown).count, 1)
        XCTAssertEqual(manager.state.intents, [.search, .shortcuts, .search])
        XCTAssertEqual(App.hideUiCount, 0)
    }

    func testResummonKeepsVisibleGateButCancelsUnshownAnchorRequest() throws {
        for shown in [false, true] {
            readiness = shown ? .ready : .settling
            summon()
            XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
            drain()
            let popover = try XCTUnwrap(popovers.last)
            dismiss()
            summon()
            popover.readiness = .ready
            popover.retryPresentation()
            drain()
            XCTAssertEqual(popover.isShown, shown)
            XCTAssertEqual(popover.showCount, shown ? 1 : 0)
            XCTAssertFalse(popover.isWaitingForAnchor)
            popover.close()
            dismiss()
        }
    }

    func testLateAnchorAfterReleaseDoesNotRequestKeyboardFocus() throws {
        readiness = .settling
        summon()
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        let popover = try XCTUnwrap(popovers.last)
        dismiss()
        popover.readiness = .ready
        popover.retryPresentation()
        drain()
        XCTAssertTrue(popover.isShown)
        XCTAssertFalse(popover.takesKeyboardFocus)
        XCTAssertEqual(App.hideUiCount, 0)
    }

    func testGateIgnoresMarketingLimitsButRechecksSessionLicenseAndOnboardingAtAnchor() throws {
        context = .init(competingUI: true, fullscreen: true, optedOut: true, messageToday: true)
        summon()
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        XCTAssertTrue(try XCTUnwrap(popovers.last).isShown)
        for blocker in [\ProPromptPresentation.Context.sessionAvailable, \.isPro, \.onboarding] {
            readiness = .settling
            XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
            drain()
            let popover = try XCTUnwrap(popovers.last)
            context[keyPath: blocker].toggle()
            popover.readiness = .ready
            popover.retryPresentation()
            drain()
            XCTAssertFalse(popover.isShown)
            XCTAssertFalse(popover.isWaitingForAnchor)
            context[keyPath: blocker].toggle()
            popover.retryPresentation()
            drain()
            XCTAssertEqual(popover.showCount, 0)
        }
    }

    func testSessionCancellationClosesVisibleAndPendingGatesWithoutRevival() throws {
        for shown in [false, true] {
            readiness = shown ? .ready : .settling
            XCTAssertFalse(manager.attemptHardGatedFeature(.extraShortcut(index: 1)))
            drain()
            let popover = try XCTUnwrap(popovers.last)
            ProPromptHost.cancelTransientPrompts()
            popover.readiness = .ready
            popover.retryPresentation()
            drain()
            XCTAssertFalse(popover.isShown)
            XCTAssertFalse(popover.isWaitingForAnchor)
            XCTAssertNil(popover.contentViewController)
        }
    }

    func testWorkspaceObserversCloseGatesOnSleepSessionExitAndSpaceChange() throws {
        let observer = ProPromptHost(observeWorkspace: true)
        defer { withExtendedLifetime(observer) {} }
        for notification in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                             NSWorkspace.activeSpaceDidChangeNotification] {
            XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
            drain()
            let popover = try XCTUnwrap(popovers.last)
            XCTAssertTrue(popover.isShown)
            NSWorkspace.shared.notificationCenter.post(name: notification, object: nil)
            drain()
            XCTAssertFalse(popover.isShown)
            XCTAssertNil(popover.contentViewController)
        }
    }

    func testPurchaseDismissalCancelsPendingAndVisibleGates() throws {
        for shown in [false, true] {
            readiness = shown ? .ready : .settling
            XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
            drain()
            let popover = try XCTUnwrap(popovers.last)
            host.dispatch(.dismissAllProWindows)
            popover.readiness = .ready
            popover.retryPresentation()
            drain()
            XCTAssertFalse(popover.isShown)
            XCTAssertNil(popover.contentViewController)
            XCTAssertFalse(ProPromptPopover.isShowing)
        }
    }

    func testVisibleExpiryAnnouncementPreventsAnAdditionalGate() {
        Day15FullUpgradeWindow.shared = VisibleExpiryWindow(size: NSSize(width: 100, height: 100))
        defer { Day15FullUpgradeWindow.shared = nil }
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        XCTAssertTrue(popovers.isEmpty)
    }

    func testMaybeLaterDismissesAndNextAttemptCanShowAgain() throws {
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        drain()
        let popover = try XCTUnwrap(popovers.last)
        let row = try XCTUnwrap(popover.contentViewController?.view.subviews.last as? NSStackView)
        let dismiss = try XCTUnwrap(row.arrangedSubviews.first as? NSButton)
        XCTAssertEqual(dismiss.title, NSLocalizedString("Maybe later", comment: ""))
        dismiss.performClick(nil)
        XCTAssertFalse(popover.isShown)
        XCTAssertTrue(checkouts.isEmpty)
        XCTAssertFalse(manager.attemptHardGatedFeature(.extraShortcut(index: 2)))
        drain()
        XCTAssertTrue(try XCTUnwrap(popovers.last).isShown)
    }

    func testExplicitGateCancelsAnOutstandingWindowHistoryLoad() {
        var complete: ((Int) -> Void)?
        ProPromptHost.windowPresentation.load(using: { complete = $0 }, canPresent: { true },
            show: { _ in XCTFail("The superseded announcement must not replace the gate") })
        XCTAssertFalse(manager.attemptHardGatedFeature(.searchInSwitcher))
        complete?(1)
        XCTAssertFalse(ProPromptHost.windowPresentation.isPending)
        drain()
        XCTAssertEqual(popovers.filter(\.isShown).count, 1)
    }

    func testEntitlementAndFirstFreePassStillAllowTheFeatureWithoutAPopover() {
        for pro in [false, true] {
            manager.state.value.isPro = pro
            manager.state.value.isTrialActive = !pro
            XCTAssertTrue(manager.attemptHardGatedFeature(.searchInSwitcher))
        }
        manager.state.value.isPro = false
        manager.state.value.isTrialActive = false
        manager.state.freePassUsed = false
        manager.state.hasSeenFullUpgrade = false
        XCTAssertTrue(manager.attemptHardGatedFeature(.extraShortcut(index: 1)))
        XCTAssertTrue(manager.isFreePassSessionActive)
        XCTAssertTrue(manager.freePassUsed)
        XCTAssertTrue(manager.hasPendingPrompt)
        XCTAssertTrue(popovers.isEmpty)
        let announced = expectation(description: "expiry announcement after the free-pass session")
        manager.onAction = { action in
            guard case .showDay15FullUpgrade(.some(.feature(.extraShortcut(index: 1)))) = action else {
                return XCTFail("The one-session pass must announce the feature that was used")
            }
            announced.fulfill()
        }
        dismiss()
        waitForExpectations(timeout: 3)
        XCTAssertFalse(manager.isFreePassSessionActive)
        XCTAssertFalse(manager.hasPendingPrompt)
    }

    private func summon() {
        SwitcherSession.current = SwitcherSession()
        manager.onSwitcherShown()
    }

    private func dismiss() {
        SwitcherSession.current = nil
        manager.onSwitcherDismissed()
    }

    private func title(_ popover: AnchoredPopover) -> String? {
        (popover.contentViewController?.view.subviews.first as? NSTextField)?.stringValue
    }

    private func getPro(_ popover: AnchoredPopover) throws -> NSButton {
        let row = try XCTUnwrap(popover.contentViewController?.view.subviews.last as? NSStackView)
        return try XCTUnwrap(row.arrangedSubviews.last as? NSButton)
    }

    private func drain() {
        let done = expectation(description: "queued presentation")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
}

private final class FlowPopover: AnchoredPopover {
    private let anchor: NSView
    var readiness = StatusItemAnchor.Readiness.ready
    var showCount = 0
    private var displayed = false
    override var isShown: Bool { displayed }

    init(anchor: NSView) {
        self.anchor = anchor
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("Tests construct popovers directly") }

    override func present(_ content: NSView, from item: NSStatusItem?, canPresent: @escaping () -> Bool,
                          onShown: (() -> Void)?) {
        super.present(content, from: anchor, canPresent: canPresent, onShown: onShown)
    }

    override func readiness(of anchor: NSView, isHidden: Bool, deadlinePassed: Bool) -> StatusItemAnchor.Readiness { readiness }

    override func showImmediately(from anchor: NSView) -> Bool {
        showCount += 1
        displayed = true
        NotificationCenter.default.post(name: NSPopover.didShowNotification, object: self)
        return true
    }

    override func showUnanchored() -> Bool { showImmediately(from: anchor) }

    override func close() {
        displayed = false
        super.close()
    }
}

private final class VisibleExpiryWindow: Day15FullUpgradeWindow {
    override var isVisible: Bool { true }
}
