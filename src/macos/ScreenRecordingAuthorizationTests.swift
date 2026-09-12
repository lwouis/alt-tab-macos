import XCTest

final class ScreenRecordingAuthorizationTests: XCTestCase {
    func testConcurrentGrantUpdatesKeepTrustedSnapshot() {
        let store = ScreenRecordingAuthorizationStore(wasGranted: false)
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            _ = store.receive(.granted)
            XCTAssertTrue(store.snapshot.model.wasGranted)
            XCTAssertEqual(store.snapshot.model.state, .granted)
        }
        store.skip()
        XCTAssertTrue(store.snapshot.isSkipped)
        _ = store.receive(.granted)
        XCTAssertFalse(store.snapshot.isSkipped)
    }

    func testPermissionTimeoutAfterKnownGrantIsTemporary() {
        var model = ScreenRecordingAuthorizationModel(wasGranted: true)

        let effects = model.receive(.temporarilyUnavailable(.timeout))

        XCTAssertEqual(model.state, .temporarilyUnavailable)
        XCTAssertEqual(effects, [.scheduleConfirmation(after: 10), .scheduleConfirmation(after: 30)])
        XCTAssertFalse(effects.contains(.openOnboarding))
    }

    func testFirstUseDenialOpensOnboarding() {
        var model = ScreenRecordingAuthorizationModel(wasGranted: false)

        let effects = model.receive(.notGranted)

        XCTAssertEqual(model.state, .needsUserReview)
        XCTAssertEqual(effects, [.openOnboarding])
    }

    func testConfirmedLaterFailureUsesPassiveReview() {
        var model = ScreenRecordingAuthorizationModel(wasGranted: true)

        _ = model.receive(.notGranted)
        _ = model.receive(.notGranted)
        let effects = model.receive(.notGranted)

        XCTAssertEqual(model.state, .needsUserReview)
        XCTAssertEqual(effects, [.showPassiveReview])
        XCTAssertFalse(effects.contains(.openOnboarding))
    }

    func testRecoveryCancelsConfirmationPeriod() {
        var model = ScreenRecordingAuthorizationModel(wasGranted: true)
        _ = model.receive(.temporarilyUnavailable(.screenCaptureKit(
            domain: "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
            code: -3811
        )))

        let effects = model.receive(.granted)

        XCTAssertEqual(model.state, .granted)
        XCTAssertEqual(effects, [.cancelConfirmations])
        XCTAssertTrue(model.wasGranted)
    }
}
