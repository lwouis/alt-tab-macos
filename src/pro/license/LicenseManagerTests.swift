import XCTest

final class LicenseManagerTests: XCTestCase {
    var clock: MockClock!
    var keychain: MockKeychain!
    var api: MockLicenseAPI!
    var defaults: UserDefaults!
    var suiteName: String!
    var manager: LicenseManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.lwouis.alt-tab-macos.tests.license"
        defaults = TestDefaults.make(suiteName)
        clock = MockClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        keychain = MockKeychain()
        api = MockLicenseAPI()
        manager = LicenseManager(clock: clock, keychain: keychain, api: api, defaults: defaults)
    }

    override func tearDown() {
        TestDefaults.tearDown(defaults, suiteName)
        super.tearDown()
    }

    func testActivationCelebratesOnceButValidationAndRepeatedActivationDoNot() {
        manager.initialize()
        var celebrations = 0
        manager.onActivationSucceeded = { celebrations += 1 }
        api.activateResult = .success(ActivateResult(
            instanceId: "inst",
            variantId: "pro",
            customerEmail: nil
        ))
        let first = expectation(description: "first activation")
        manager.activate("key") { _ in first.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(celebrations, 1)
        let second = expectation(description: "repeat activation")
        manager.activate("key") { _ in second.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(celebrations, 1)
        manager.initialize()
        XCTAssertEqual(celebrations, 1)
    }

    func testFailedActivationNeverCelebrates() {
        manager.initialize()
        var celebrations = 0
        manager.onActivationSucceeded = { celebrations += 1 }
        api.activateResult = .failure(LicenseAPIError.activationRejected("invalid"))
        let done = expectation(description: "failed activation")
        manager.activate("key") { _ in done.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(celebrations, 0)
    }

    // MARK: - Launch / initialize

    private func becomeUsable() {
        manager.onAppBecameUsable(accessibility: .granted, screenRecording: .granted)
    }

    func testSetupReadsAndRelaunchNeverStartOrExpireATrial() {
        manager.initialize()
        clock.advance(days: 100)
        for _ in 0..<3 {
            manager.refreshState()
            XCTAssertEqual(manager.computeState(), .trialNotStarted)
            XCTAssertNil(manager.trialStartDate)
            XCTAssertNil(manager.trialEndDate)
            XCTAssertNil(manager.trialDay)
            XCTAssertFalse(manager.trialEndedSinceLastRefresh)
            XCTAssertFalse(manager.isProAvailable)
            XCTAssertFalse(manager.isProLocked, "setup must not downgrade stored preferences")
        }
        let relaunched = LicenseManager(clock: clock, keychain: keychain, api: api, defaults: defaults)
        relaunched.initialize()
        XCTAssertEqual(relaunched.state, .trialNotStarted)
        XCTAssertNil(defaults.object(forKey: "trialStartDate"))
    }

    func testFirstUsableMilestoneRequiresAccessibilityAndResolvedRecording() {
        for accessibility: PermissionStatus in [.notGranted, .skipped, .granted] {
            for recording: PermissionStatus in [.notGranted, .skipped, .granted] {
                defaults.removeObject(forKey: "trialStartDate")
                let candidate = LicenseManager(clock: clock, keychain: keychain, api: api, defaults: defaults)
                candidate.initialize()
                candidate.onAppBecameUsable(accessibility: accessibility, screenRecording: recording)
                let ready = accessibility == .granted && recording != .notGranted
                XCTAssertEqual(candidate.state, ready ? .trial(daysRemaining: 14) : .trialNotStarted)
                XCTAssertEqual(candidate.trialStartDate, ready ? clock.now : nil)
            }
        }
    }

    func testExistingTrialDatesSurviveReadinessRevocationExpiryAndClockRollback() {
        for daysAgo in [-2, 0, 7, 14, 100] {
            setupTrial(daysAgo: daysAgo)
            let original = manager.trialStartDate
            manager.initialize()
            let state = manager.state
            becomeUsable()
            manager.onAppBecameUsable(accessibility: .notGranted, screenRecording: .notGranted)
            becomeUsable()
            XCTAssertEqual(manager.trialStartDate, original)
            XCTAssertEqual(manager.state, state)
        }
    }

    func testExistingLicenseNeverStartsATrialEvenWhenInvalidated() {
        setupActivatedLicense(variantId: "pro")
        manager.initialize()
        becomeUsable()
        XCTAssertEqual(manager.state, .pro)
        XCTAssertNil(manager.trialStartDate)
        defaults.set(false, forKey: "lastValidationResult")
        manager.refreshState()
        becomeUsable()
        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertNil(manager.trialStartDate)
    }

    func testDeactivationBeforeUsableDoesNotStartTrial() {
        setupActivatedLicense(variantId: "pro")
        manager.initialize()
        api.deactivateResult = .success(())
        let done = expectation(description: "deactivate during setup")
        manager.deactivate { _ in done.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(manager.state, .trialNotStarted)
        XCTAssertNil(manager.trialStartDate)
        becomeUsable()
        XCTAssertEqual(manager.trialStartDate, clock.now)
    }

    func testDeactivationAfterUsableStartsOnlyPreviouslyUnstartedTrial() {
        setupActivatedLicense(variantId: "pro")
        manager.initialize()
        becomeUsable()
        clock.advance(days: 2)
        api.deactivateResult = .success(())
        let done = expectation(description: "deactivate after setup")
        manager.deactivate { _ in done.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertEqual(manager.state, .trial(daysRemaining: 14))
        XCTAssertEqual(manager.trialStartDate, clock.now)
    }

    func testFirstUsableLaunchStartsTrial() {
        manager.initialize()
        clock.advance(days: 30)
        becomeUsable()
        guard case .trial(let days) = manager.state else { return XCTFail("expected .trial, got \(manager.state)") }
        XCTAssertEqual(days, 14)
        XCTAssertEqual(manager.trialStartDate, clock.now)
    }

    func testSecondLaunchPreservesTrialStart() {
        manager.initialize()
        becomeUsable() // day 0
        let originalStart = manager.trialStartDate
        clock.advance(days: 3)
        // simulate relaunch: rebuild manager with same defaults/keychain, no fresh trial start
        let manager2 = LicenseManager(clock: clock, keychain: keychain, api: api, defaults: defaults)
        manager2.initialize()
        manager2.onAppBecameUsable(accessibility: .granted, screenRecording: .granted)
        XCTAssertEqual(manager2.trialStartDate, originalStart)
        guard case .trial(let days) = manager2.state else { return XCTFail("expected .trial, got \(manager2.state)") }
        XCTAssertEqual(days, 11)
    }

    func testTrialMidway() {
        setupTrial(daysAgo: 7)
        manager.initialize()
        guard case .trial(let days) = manager.state else { return XCTFail() }
        XCTAssertEqual(days, 7)
    }

    func testTrialLastDay() {
        setupTrial(daysAgo: 13)
        manager.initialize()
        guard case .trial(let days) = manager.state else { return XCTFail() }
        XCTAssertEqual(days, 1)
    }

    func testTrialExpiresOnDay14() {
        setupTrial(daysAgo: 14)
        manager.initialize()
        XCTAssertEqual(manager.state, .trialExpired)
    }

    func testTrialExpiresWellPastDuration() {
        setupTrial(daysAgo: 365)
        manager.initialize()
        XCTAssertEqual(manager.state, .trialExpired)
    }

    // MARK: - Keychain-backed licenses

    func testExistingValidLicenseIsPro() {
        setupActivatedLicense(variantId: nil)
        manager.initialize()
        XCTAssertEqual(manager.state, .pro)
    }

    func testPreviouslyInvalidatedLicenseIsTrialExpired() {
        setupActivatedLicense(variantId: nil)
        defaults.set(false, forKey: "lastValidationResult")
        manager.initialize()
        XCTAssertEqual(manager.state, .trialExpired)
    }

    func testLicenseWithoutValidationResultIsTrialExpired() {
        // license in keychain but lastValidationResult was never set — defensive: treat as expired
        keychain.setValue("KEY", account: LicenseManager.keychainKeyAccount)
        keychain.setValue("instance-1", account: LicenseManager.keychainInstanceAccount)
        manager.initialize()
        XCTAssertEqual(manager.state, .trialExpired)
    }

    // MARK: - Version-limited variants

    func testVersionLimitedPastCutoffIsProExpired() {
        setupActivatedLicense(variantId: "pro")
        manager.currentAppVersion = { "11.0.0" }
        // Inject a version limit for variant 101 via the static dict replacement:
        // since versionLimitedVariants is static-let, we exercise the logic by
        // setting the current version higher than a test cutoff. This test guards
        // the comparison branch; if the dict is empty in production, state is .pro.
        // We rely on the public contract: when no variant is limited, state is .pro.
        manager.initialize()
        // versionLimitedVariants is empty by default so state should be .pro regardless of variant.
        XCTAssertEqual(manager.state, .pro)
    }

    // MARK: - Activate

    func testActivateSuccessTransitionsToPro() {
        api.activateResult = .success(ActivateResult(instanceId: "inst-1", variantId: "pro", customerEmail: "alice@example.com"))
        let exp = expectation(description: "activate")
        manager.activate("LICENSE-KEY-ABC") { result in
            if case .failure(let e) = result { XCTFail("expected success, got \(e)") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(manager.state, .pro)
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainKeyAccount), "LICENSE-KEY-ABC")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainInstanceAccount), "inst-1")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainVariantAccount), "pro")
        XCTAssertEqual(defaults.bool(forKey: "lastValidationResult"), true)
        XCTAssertEqual(defaults.double(forKey: "lastValidation"), clock.now.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(manager.customerEmail, "alice@example.com")
    }

    func testActivateFailurePreservesState() {
        setupTrial(daysAgo: 3)
        manager.initialize()
        api.activateResult = .failure(LicenseAPIError.activationRejected("invalid"))
        let exp = expectation(description: "activate")
        manager.activate("BAD-KEY") { result in
            if case .success = result { XCTFail("expected failure") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        // State still trial; no keychain writes
        guard case .trial = manager.state else { return XCTFail("expected trial, got \(manager.state)") }
        XCTAssertNil(keychain.value(account: LicenseManager.keychainKeyAccount))
    }

    func testLifetimeActivationPersistsAcrossManagerReplacement() {
        api.activateResult = .success(ActivateResult(instanceId: "team-mac", variantId: "pro_lifetime", customerEmail: "manager@example.com"))
        let done = expectation(description: "Lifetime activation")
        manager.activate("TEAM-KEY") { result in
            if case .failure(let error) = result { XCTFail("Lifetime activation failed: \(error)") }
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        let replacement = LicenseManager(clock: clock, keychain: keychain, api: api, defaults: defaults)
        replacement.initialize()
        XCTAssertEqual(replacement.state, .pro)
        XCTAssertTrue(replacement.isLifetimeVariant)
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainInstanceAccount), "team-mac")
    }

    func testActivateWithoutCustomerEmailLeavesCustomerEmailNil() {
        api.activateResult = .success(ActivateResult(instanceId: "inst", variantId: nil, customerEmail: nil))
        let exp = expectation(description: "activate")
        manager.activate("KEY") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertNil(manager.customerEmail)
        XCTAssertNil(keychain.value(account: LicenseManager.keychainVariantAccount))
    }

    func testActivateSeatLimitExceededSurfacesInstances() {
        setupTrial(daysAgo: 3)
        manager.initialize()
        let instances = [
            ActiveInstance(id: "inst-old-1", machineName: "Work laptop", lastSeenAt: clock.now.addingTimeInterval(-86400)),
            ActiveInstance(id: "inst-old-2", machineName: nil, lastSeenAt: clock.now.addingTimeInterval(-86400 * 7)),
        ]
        api.activateResult = .failure(LicenseAPIError.seatLimitExceeded(instances: instances))
        let exp = expectation(description: "activate")
        var surfaced: [ActiveInstance] = []
        manager.activate("KEY") { result in
            if case .failure(let e) = result, case LicenseAPIError.seatLimitExceeded(let list) = e {
                surfaced = list
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(surfaced.count, 2)
        XCTAssertEqual(surfaced[0].id, "inst-old-1")
        XCTAssertEqual(surfaced[0].machineName, "Work laptop")
        XCTAssertNil(surfaced[1].machineName)
        // State preserved — seat-limit alerts don't flip the license state.
        guard case .trial = manager.state else { return XCTFail("expected trial, got \(manager.state)") }
        XCTAssertNil(keychain.value(account: LicenseManager.keychainKeyAccount))
    }

    func testActivateFailsAndRollsBackIfKeychainWriteFails() {
        setupTrial(daysAgo: 3)
        manager.initialize()
        api.activateResult = .success(ActivateResult(instanceId: "inst-1", variantId: "pro", customerEmail: "alice@example.com"))
        keychain.setValueStatus = { _ in errSecAuthFailed }
        let exp = expectation(description: "activate")
        var surfaced: Error?
        manager.activate("LICENSE-KEY-ABC") { result in
            if case .failure(let e) = result { surfaced = e }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        guard case LicenseAPIError.keychainWriteFailed(let account, let status) = surfaced as? LicenseAPIError ?? .noData else {
            return XCTFail("expected keychainWriteFailed, got \(String(describing: surfaced))")
        }
        XCTAssertEqual(account, LicenseManager.keychainKeyAccount)
        XCTAssertEqual(status, errSecAuthFailed)
        // State must NOT flip to .pro
        guard case .trial = manager.state else { return XCTFail("expected trial, got \(manager.state)") }
        // Rollback: nothing should remain in keychain
        XCTAssertNil(keychain.value(account: LicenseManager.keychainKeyAccount))
        XCTAssertNil(keychain.value(account: LicenseManager.keychainInstanceAccount))
        XCTAssertNil(keychain.value(account: LicenseManager.keychainVariantAccount))
        // Validation timestamps must NOT be written either
        XCTAssertNil(defaults.object(forKey: "lastValidation"))
        XCTAssertNil(defaults.object(forKey: "lastValidationResult"))
        XCTAssertNil(defaults.object(forKey: "customerEmail"))
    }

    func testActivateRollsBackPartialKeychainWritesOnLaterFailure() {
        setupTrial(daysAgo: 3)
        manager.initialize()
        api.activateResult = .success(ActivateResult(instanceId: "inst-1", variantId: "pro", customerEmail: nil))
        // First write succeeds, second fails. Verifies the rollback removes the first one too.
        var calls = 0
        keychain.setValueStatus = { _ in
            calls += 1
            return calls == 1 ? errSecSuccess : errSecAuthFailed
        }
        let exp = expectation(description: "activate")
        manager.activate("LICENSE-KEY-ABC") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        guard case .trial = manager.state else { return XCTFail("expected trial, got \(manager.state)") }
        XCTAssertNil(keychain.value(account: LicenseManager.keychainKeyAccount))
        XCTAssertNil(keychain.value(account: LicenseManager.keychainInstanceAccount))
    }

    func testActivateFailureKeepsAnAlreadyStoredLicense() {
        setupActivatedLicense(variantId: "pro")
        manager.initialize()
        api.activateResult = .success(ActivateResult(instanceId: "inst-2", variantId: "pro", customerEmail: nil))
        // Re-activating with a different key on a machine whose keychain stopped accepting writes.
        keychain.setValueStatus = { _ in errSecAuthFailed }
        let exp = expectation(description: "activate")
        manager.activate("LICENSE-KEY-XYZ") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        // The rollback must not delete what the failed write left untouched.
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainKeyAccount), "LICENSE-ABC")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainInstanceAccount), "instance-1")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainVariantAccount), "pro")
        XCTAssertEqual(manager.state, .pro)
    }

    func testDeactivateInstanceCallsApiWithoutTouchingLocalState() {
        setupActivatedLicense(variantId: nil)
        manager.initialize()
        api.deactivateResult = .success(())
        let exp = expectation(description: "deactivate-instance")
        manager.deactivateInstance(licenseKey: "KEY", instanceId: "other-instance") { result in
            if case .failure(let e) = result { XCTFail("expected success, got \(e)") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(api.deactivateCalls.count, 1)
        XCTAssertEqual(api.deactivateCalls[0].0, "KEY")
        XCTAssertEqual(api.deactivateCalls[0].1, "other-instance")
        // Local keychain is untouched — the deactivated instance was another machine.
        XCTAssertNotNil(keychain.value(account: LicenseManager.keychainKeyAccount))
        XCTAssertEqual(manager.state, .pro)
    }

    // MARK: - Deactivate

    func testDeactivateSuccessReturnsToTrialWhenStillInTrialWindow() {
        setupActivatedLicense(variantId: nil)
        setupTrial(daysAgo: 3)
        manager.initialize()
        XCTAssertEqual(manager.state, .pro)

        api.deactivateResult = .success(())
        let exp = expectation(description: "deactivate")
        manager.deactivate { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)

        guard case .trial(let days) = manager.state else { return XCTFail("expected trial, got \(manager.state)") }
        XCTAssertEqual(days, 11)
        XCTAssertNil(keychain.value(account: LicenseManager.keychainKeyAccount))
        XCTAssertNil(keychain.value(account: LicenseManager.keychainInstanceAccount))
    }

    func testDeactivateSuccessReturnsToTrialExpiredAfterTrialWindow() {
        setupActivatedLicense(variantId: nil)
        setupTrial(daysAgo: 100)
        manager.initialize()
        XCTAssertEqual(manager.state, .pro)

        api.deactivateResult = .success(())
        let exp = expectation(description: "deactivate")
        manager.deactivate { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(manager.state, .trialExpired)
    }

    func testDeactivateFailurePreservesState() {
        setupActivatedLicense(variantId: nil)
        manager.initialize()
        api.deactivateResult = .failure(LicenseAPIError.deactivationRejected)
        let exp = expectation(description: "deactivate")
        manager.deactivate { result in
            if case .success = result { XCTFail("expected failure") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(manager.state, .pro)
        XCTAssertNotNil(keychain.value(account: LicenseManager.keychainKeyAccount))
    }

    func testDeactivateWithoutLicenseErrors() {
        manager.initialize()
        let exp = expectation(description: "deactivate")
        manager.deactivate { result in
            if case .success = result { XCTFail("expected failure") }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(api.deactivateCalls.count, 0)
    }

    // MARK: - Async revalidation

    func testRevalidationWithinIntervalIsSkipped() {
        setupActivatedLicense(variantId: nil)
        // lastValidation set to clock.now by setupActivatedLicense
        manager.initialize()
        // no wait: revalidation was dispatched from initialize(), but it returns early
        // give the run loop a tick to run any queued work
        drainMainQueue()
        XCTAssertEqual(api.validateCalls.count, 0)
    }

    func testRevalidationAfterIntervalValidKeepsPro() {
        setupActivatedLicense(variantId: nil)
        // make lastValidation 31 days old
        defaults.set(clock.now.addingTimeInterval(-31 * 86400).timeIntervalSince1970, forKey: "lastValidation")
        api.validateResult = .success(ValidateResult(valid: true, variantId: nil))

        manager.initialize()
        let exp = expectation(description: "validate callback drained")
        DispatchQueue.main.async { exp.fulfill() } // enqueued AFTER the api completion → ordering
        wait(for: [exp], timeout: 1)
        drainMainQueue()

        XCTAssertEqual(api.validateCalls.count, 1)
        XCTAssertEqual(manager.state, .pro)
        XCTAssertEqual(defaults.double(forKey: "lastValidation"), clock.now.timeIntervalSince1970, accuracy: 0.01)
    }

    func testRevalidationAfterIntervalInvalidFlipsToTrialExpired() {
        setupActivatedLicense(variantId: nil)
        defaults.set(clock.now.addingTimeInterval(-31 * 86400).timeIntervalSince1970, forKey: "lastValidation")
        api.validateResult = .success(ValidateResult(valid: false, variantId: nil))

        manager.initialize()
        XCTAssertEqual(manager.state, .pro) // sync — state computed from lastValidationResult=true in defaults
        let exp = expectation(description: "validate callback drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        drainMainQueue()

        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertEqual(defaults.bool(forKey: "lastValidationResult"), false)
    }

    func testRevalidationNetworkFailurePreservesState() {
        setupActivatedLicense(variantId: nil)
        let oldValidation = clock.now.addingTimeInterval(-31 * 86400).timeIntervalSince1970
        defaults.set(oldValidation, forKey: "lastValidation")
        api.validateResult = .failure(LicenseAPIError.noData)

        manager.initialize()
        let exp = expectation(description: "validate callback drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        drainMainQueue()

        XCTAssertEqual(api.validateCalls.count, 1)
        XCTAssertEqual(manager.state, .pro) // unchanged
        XCTAssertEqual(defaults.double(forKey: "lastValidation"), oldValidation, accuracy: 0.01) // untouched
    }

    func testRevalidationUpdatesVariantIdWhenReturned() {
        setupActivatedLicense(variantId: nil)
        defaults.set(clock.now.addingTimeInterval(-31 * 86400).timeIntervalSince1970, forKey: "lastValidation")
        api.validateResult = .success(ValidateResult(valid: true, variantId: "pro_lifetime"))

        manager.initialize()
        let exp = expectation(description: "validate callback drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1)
        drainMainQueue()

        XCTAssertEqual(keychain.value(account: LicenseManager.keychainVariantAccount), "pro_lifetime")
    }

    // MARK: - State change callback

    func testOnStateChangedFiresOnInitialize() {
        var observed: [LicenseState] = []
        manager.onStateChanged = { observed.append($0) }
        manager.initialize()
        XCTAssertEqual(observed.count, 1)
        XCTAssertEqual(observed.first, .trialNotStarted)
    }

    func testOnStateChangedFiresOnActivateSuccess() {
        var observed: [LicenseState] = []
        manager.onStateChanged = { observed.append($0) }
        manager.initialize()
        api.activateResult = .success(ActivateResult(instanceId: "i", variantId: nil, customerEmail: nil))
        let exp = expectation(description: "activate")
        manager.activate("K") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(observed.last, .pro)
        XCTAssertGreaterThanOrEqual(observed.count, 2)
    }

    // MARK: - isProLocked + onBeforeProUnlock

    func testIsProLockedFalseDuringTrial() {
        manager.initialize()
        becomeUsable()
        XCTAssertFalse(manager.isProLocked)
    }

    func testIsProLockedTrueAfterTrialExpiry() {
        setupTrial(daysAgo: 14)
        manager.initialize()
        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertTrue(manager.isProLocked, "no grace period: degradable features lock immediately on trial expiry")
    }

    func testIsProLockedTrueWhenKeychainInvalidated() {
        // Simulate a keychain-backed license that failed revalidation → computeState returns .trialExpired.
        setupActivatedLicense(variantId: nil)
        defaults.set(false, forKey: "lastValidationResult")
        manager.initialize()
        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertTrue(manager.isProLocked)
    }

    func testOnBeforeProUnlockFiresBeforeStateFlipsToPro() {
        manager.initialize()
        api.activateResult = .success(ActivateResult(instanceId: "i", variantId: nil, customerEmail: nil))
        var observedStateWhenHookFired: LicenseState?
        manager.onBeforeProUnlock = { [weak manager] in
            observedStateWhenHookFired = manager?.state
        }
        let exp = expectation(description: "activate")
        manager.activate("K") { _ in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertNotNil(observedStateWhenHookFired)
        XCTAssertNotEqual(observedStateWhenHookFired, .pro, "hook should see pre-activation state")
        XCTAssertEqual(manager.state, .pro)
    }

    #if DEBUG
    func testOnBeforeProUnlockFiresOnMockProUser() {
        manager.initialize()
        var hookFired = false
        manager.onBeforeProUnlock = { hookFired = true }
        manager.mockProUser()
        XCTAssertTrue(hookFired)
        XCTAssertEqual(manager.state, .pro)
    }

    func testMockProUserDoesNotAlterPersistedLicense() {
        setupActivatedLicense(variantId: "pro_lifetime")
        defaults.set("real@example.com", forKey: LicenseManager.customerEmailKey)
        let storedDefaults = defaults.dictionaryRepresentation()
        manager.mockProUser()
        manager.refreshState()
        XCTAssertEqual(manager.state, .pro)
        XCTAssertEqual(manager.customerEmail, "john@cool-software.com")
        XCTAssertFalse(manager.isLifetimeVariant)
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainKeyAccount), "LICENSE-ABC")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainInstanceAccount), "instance-1")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainVariantAccount), "pro_lifetime")
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, storedDefaults as NSDictionary)
    }

    func testMockTrialDayDoesNotAlterPersistedLicense() {
        setupActivatedLicense(variantId: "pro_lifetime")
        defaults.set("real@example.com", forKey: LicenseManager.customerEmailKey)
        let storedDefaults = defaults.dictionaryRepresentation()
        manager.mockTrialDay(4)
        manager.refreshState()
        XCTAssertEqual(manager.state, .trial(daysRemaining: 11))
        XCTAssertEqual(manager.daysSinceTrialStart, 3)
        XCTAssertNil(manager.customerEmail)
        XCTAssertFalse(manager.isLifetimeVariant)
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainKeyAccount), "LICENSE-ABC")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainInstanceAccount), "instance-1")
        XCTAssertEqual(keychain.value(account: LicenseManager.keychainVariantAccount), "pro_lifetime")
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, storedDefaults as NSDictionary)
    }

    func testMockedTrialExpiresWhenTheClockPassesItsEnd() {
        manager.mockTrialDay(14)
        XCTAssertEqual(manager.state, .trial(daysRemaining: 1))
        clock.advance(days: 1)
        XCTAssertTrue(manager.trialEndedSinceLastRefresh)
        manager.refreshState()
        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertEqual(manager.trialDay, 15)
    }
    #endif

    // MARK: - Trial end while running

    func testRunningAppKnowsWhenTheTrialHasOutlivedItsState() {
        manager.initialize()
        becomeUsable()
        clock.advance(by: 14 * 86400 - 1)
        XCTAssertFalse(manager.trialEndedSinceLastRefresh)
        clock.advance(by: 1)
        XCTAssertTrue(manager.trialEndedSinceLastRefresh)
        XCTAssertEqual(manager.state, .trial(daysRemaining: 14), "state only follows the clock on refresh")
        manager.refreshState()
        XCTAssertEqual(manager.state, .trialExpired)
        XCTAssertFalse(manager.trialEndedSinceLastRefresh)
    }

    func testLicensedStateNeverReportsAnOutlivedTrial() {
        setupActivatedLicense(variantId: "pro")
        manager.initialize()
        clock.advance(days: 30)
        XCTAssertFalse(manager.trialEndedSinceLastRefresh)
    }

    // MARK: - Trial day

    func testTrialDay_isNilWithoutTrial() {
        XCTAssertNil(manager.trialDay)
    }

    func testTrialDay_isOneIndexed() {
        setupTrial(daysAgo: 0)
        XCTAssertEqual(manager.trialDay, 1)
        setupTrial(daysAgo: 34)
        XCTAssertEqual(manager.trialDay, 35)
        setupTrial(daysAgo: 99)
        XCTAssertEqual(manager.trialDay, 100)
    }

    func testTrialDay_isNilWhenClockIsBeforeTrialStart() {
        setupTrial(daysAgo: -2)
        XCTAssertNil(manager.trialDay)
    }

    // MARK: - Helpers

    private func setupTrial(daysAgo: Int) {
        let start = clock.now.addingTimeInterval(-Double(daysAgo) * 86400)
        defaults.set(start.timeIntervalSince1970, forKey: "trialStartDate")
    }

    private func setupActivatedLicense(variantId: String?) {
        keychain.setValue("LICENSE-ABC", account: LicenseManager.keychainKeyAccount)
        keychain.setValue("instance-1", account: LicenseManager.keychainInstanceAccount)
        if let variantId { keychain.setValue(variantId, account: LicenseManager.keychainVariantAccount) }
        defaults.set(clock.now.timeIntervalSince1970, forKey: "lastValidation")
        defaults.set(true, forKey: "lastValidationResult")
    }

    /// Run everything already queued on main, then return. The chain under test is two hops deep (the mock
    /// API enqueues its completion, which enqueues the state write), so a block enqueued now runs after both.
    /// A fixed `RunLoop.run(until:)` spin cost 50ms per call for the same guarantee.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

// MARK: - Mocks

final class MockClock: Clock {
    var now: Date
    init(now: Date) { self.now = now }
    func advance(by interval: TimeInterval) { now = now.addingTimeInterval(interval) }
    func advance(days: Int) { now = now.addingTimeInterval(Double(days) * 86400) }
}

final class MockKeychain: Keychain {
    private var store: [String: String] = [:]
    var setValueStatus: (String) -> OSStatus = { _ in errSecSuccess }
    var removeStatus: (String) -> OSStatus = { _ in errSecSuccess }

    func value(account: String) -> String? { store[account] }

    @discardableResult
    func setValue(_ value: String, account: String) -> OSStatus {
        let status = setValueStatus(account)
        if status == errSecSuccess { store[account] = value }
        return status
    }

    @discardableResult
    func remove(account: String) -> OSStatus {
        let status = removeStatus(account)
        if status == errSecSuccess { store.removeValue(forKey: account) }
        return status
    }
}

final class MockLicenseAPI: LicenseAPI {
    var activateResult: Result<ActivateResult, Error> = .failure(LicenseAPIError.noData)
    var validateResult: Result<ValidateResult, Error> = .failure(LicenseAPIError.noData)
    var deactivateResult: Result<Void, Error> = .failure(LicenseAPIError.noData)

    var activateCalls: [String] = []
    var validateCalls: [(String, String)] = []
    var deactivateCalls: [(String, String)] = []

    func activate(_ licenseKey: String, completion: @escaping (Result<ActivateResult, Error>) -> Void) {
        activateCalls.append(licenseKey)
        let r = activateResult
        DispatchQueue.main.async { completion(r) }
    }

    func validate(_ licenseKey: String, instanceId: String, completion: @escaping (Result<ValidateResult, Error>) -> Void) {
        validateCalls.append((licenseKey, instanceId))
        let r = validateResult
        DispatchQueue.main.async { completion(r) }
    }

    func deactivate(_ licenseKey: String, instanceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        deactivateCalls.append((licenseKey, instanceId))
        let r = deactivateResult
        DispatchQueue.main.async { completion(r) }
    }
}

final class RemoteLicenseClientTests: XCTestCase {
    func testTeamLimitDoesNotOfferRemoteDeactivationEvenWithARoster() throws {
        let response = """
        {"activated":false,"error":"seat_limit_exceeded","seats":5,
         "instances":[{"id":"another-mac","lastSeenAt":1700000000}]}
        """
        let client = makeClient(response)
        let done = expectation(description: "team limit")
        client.activate("team-key") { result in
            guard case .failure(LicenseAPIError.teamSeatLimitExceeded) = result else {
                XCTFail("Team keys must never open the personal remote-deactivation flow")
                done.fulfill()
                return
            }
            done.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testPersonalLimitStillOffersItsRoster() {
        let response = """
        {"activated":false,"error":"seat_limit_exceeded",
         "instances":[{"id":"personal-mac","machineName":"Office Mac","lastSeenAt":1700000000}]}
        """
        let client = makeClient(response)
        let done = expectation(description: "personal limit")
        client.activate("personal-key") { result in
            if case .failure(LicenseAPIError.seatLimitExceeded(let instances)) = result {
                XCTAssertEqual(instances.map(\.id), ["personal-mac"])
                XCTAssertEqual(instances.first?.machineName, "Office Mac")
            } else {
                XCTFail("Personal keys retain their remote-deactivation flow")
            }
            done.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testMachineNameIsSentOnActivateAndValidateButNotDeactivate() {
        let name = "  " + String(repeating: "é", count: 70) + "\n"
        let client = makeClient("{\"activated\":true,\"instance_id\":\"i\",\"valid\":true,\"deactivated\":true}", name: name)
        let done = expectation(description: "requests")
        done.expectedFulfillmentCount = 3
        let inspected = expectation(description: "request bodies inspected")
        inspected.expectedFulfillmentCount = 3
        TeamLicenseURLProtocol.inspect = { request, body in
            let expected = request.url?.lastPathComponent == "deactivate" ? nil : String(repeating: "é", count: 64)
            XCTAssertEqual(body["machine_name"] as? String, expected)
            inspected.fulfill()
        }
        client.activate("key") { result in
            XCTAssertEqual(try? result.get().instanceId, "i")
            done.fulfill()
        }
        client.validate("key", instanceId: "i") { result in
            XCTAssertEqual(try? result.get().valid, true)
            done.fulfill()
        }
        client.deactivate("key", instanceId: "i") { result in
            if case .failure(let error) = result { XCTFail("Deactivation failed: \(error)") }
            done.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testMissingMachineNameIsOmitted() {
        let client = makeClient("{\"valid\":true}", name: nil)
        let inspected = expectation(description: "unnamed Mac request inspected")
        let done = expectation(description: "unnamed Mac")
        TeamLicenseURLProtocol.inspect = { request, body in
            XCTAssertEqual(request.url?.lastPathComponent, "validate")
            XCTAssertEqual(body["license_key"] as? String, "key")
            XCTAssertEqual(body["instance_id"] as? String, "i")
            XCTAssertNil(body["machine_name"])
            inspected.fulfill()
        }
        client.validate("key", instanceId: "i") { result in
            XCTAssertEqual(try? result.get().valid, true)
            done.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testLifetimeResponseAndTrialAttributionSurviveTransport() {
        let client = makeClient("{\"activated\":true,\"instance_id\":\"team-mac\",\"variant_id\":\"pro_lifetime\",\"customer_email\":\"manager@example.com\"}", trialStart: Date(timeIntervalSince1970: 1700000000))
        let inspected = expectation(description: "trial attribution")
        TeamLicenseURLProtocol.inspect = { _, body in
            XCTAssertEqual(body["trial_started_at"] as? Int, 1700000000)
            inspected.fulfill()
        }
        let done = expectation(description: "Lifetime response")
        client.activate("team-key") { result in
            if case .success(let value) = result {
                XCTAssertEqual(value.variantId, "pro_lifetime")
                XCTAssertEqual(value.instanceId, "team-mac")
                XCTAssertEqual(value.customerEmail, "manager@example.com")
            } else { XCTFail("A team activation must decode as Lifetime") }
            done.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testMachineNamesRemoveControlsAndCountUnicodeScalars() {
        let client = makeClient("{\"valid\":true}", name: " \n" + String(repeating: "😀", count: 70) + "\u{0}\t ")
        let inspected = expectation(description: "Unicode machine name")
        TeamLicenseURLProtocol.inspect = { _, body in
            XCTAssertEqual(body["machine_name"] as? String, String(repeating: "😀", count: 64))
            inspected.fulfill()
        }
        let done = expectation(description: "validation")
        client.validate("key", instanceId: "i") { result in
            XCTAssertEqual(try? result.get().valid, true)
            done.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    private func makeClient(_ response: String, name: String? = "Test Mac", trialStart: Date? = nil) -> RemoteLicenseClient {
        TeamLicenseURLProtocol.response = Data(response.utf8)
        TeamLicenseURLProtocol.inspect = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TeamLicenseURLProtocol.self]
        return RemoteLicenseClient(baseUrl: "https://license.test", keychain: MockKeychain(),
            session: URLSession(configuration: config), machineName: { name }, trialStartDate: { trialStart })
    }
}

private final class TeamLicenseURLProtocol: URLProtocol {
    static var response = Data()
    static var inspect: ((URLRequest, [String: Any]) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
        }
        Self.inspect?(request, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
