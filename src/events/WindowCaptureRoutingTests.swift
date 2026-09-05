import XCTest

final class WindowCaptureRoutingTests: XCTestCase {
    func testSwitcherSessionActivityStateTracksUpdates() {
        let activity = SwitcherSessionActivity()

        XCTAssertFalse(activity.isActive)
        activity.setActive(true)
        XCTAssertTrue(activity.isActive)
        activity.setActive(false)
        XCTAssertFalse(activity.isActive)
    }

    func testSwitcherSessionActivityStateIsVisibleAcrossQueues() {
        let activity = SwitcherSessionActivity()
        let queue = DispatchQueue(label: "SwitcherSessionActivityTests")

        activity.setActive(true)
        XCTAssertTrue(queue.sync { activity.isActive })
        queue.sync { activity.setActive(false) }
        XCTAssertFalse(activity.isActive)
    }

    func testWindowServerCaptureUsesPrimaryImage() {
        var fallbackCalls = 0

        let image = WindowServerCaptureFallback.capture(
            primary: { "primary" },
            fallback: {
                fallbackCalls += 1
                return "fallback"
            })

        XCTAssertEqual(image, "primary")
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testWindowServerCaptureUsesFallbackWhenPrimaryIsEmpty() {
        var fallbackCalls = 0

        let image = WindowServerCaptureFallback.capture(
            primary: { nil as String? },
            fallback: {
                fallbackCalls += 1
                return "fallback"
            })

        XCTAssertEqual(image, "fallback")
        XCTAssertEqual(fallbackCalls, 1)
    }

    func testWindowServerCaptureStaysEmptyWhenBothMethodsFail() {
        let image = WindowServerCaptureFallback.capture(
            primary: { nil as String? },
            fallback: { nil as String? })

        XCTAssertNil(image)
    }

    func testMacOS27UsesWindowServerForTrustedThumbnails() {
        XCTAssertEqual(WindowCaptureRouting.backend(
            macOSMajorVersion: 27,
            kind: .thumbnail,
            hasTrustedGrantHistory: true,
            switcherIsActive: true,
            backgroundCaptureIsEnabled: false), .windowServer)
    }

    func testMacOS27UsesScreenCaptureKitForFocusedPreview() {
        XCTAssertEqual(WindowCaptureRouting.backend(
            macOSMajorVersion: 27,
            kind: .focusedPreview,
            hasTrustedGrantHistory: true,
            switcherIsActive: true,
            backgroundCaptureIsEnabled: false), .screenCaptureKit)
    }

    func testMacOS26KeepsScreenCaptureKitThumbnailBackend() {
        XCTAssertEqual(WindowCaptureRouting.backend(
            macOSMajorVersion: 26,
            kind: .thumbnail,
            hasTrustedGrantHistory: true,
            switcherIsActive: true,
            backgroundCaptureIsEnabled: false), .screenCaptureKit)
    }

    func testOlderMacOSKeepsWindowServerThumbnailBackend() {
        XCTAssertEqual(WindowCaptureRouting.backend(
            macOSMajorVersion: 25,
            kind: .thumbnail,
            hasTrustedGrantHistory: true,
            switcherIsActive: true,
            backgroundCaptureIsEnabled: false), .windowServer)
    }

    func testBackgroundCaptureDisabledReturnsNoBackend() {
        XCTAssertNil(WindowCaptureRouting.backend(
            macOSMajorVersion: 27,
            kind: .thumbnail,
            hasTrustedGrantHistory: true,
            switcherIsActive: false,
            backgroundCaptureIsEnabled: false))
    }

    func testBackgroundCaptureEnabledUsesSafeMacOS27Backend() {
        XCTAssertEqual(WindowCaptureRouting.backend(
            macOSMajorVersion: 27,
            kind: .thumbnail,
            hasTrustedGrantHistory: true,
            switcherIsActive: false,
            backgroundCaptureIsEnabled: true), .windowServer)
    }

    func testFocusedPreviewNeedsAnActiveSwitcher() {
        XCTAssertNil(WindowCaptureRouting.backend(
            macOSMajorVersion: 27,
            kind: .focusedPreview,
            hasTrustedGrantHistory: true,
            switcherIsActive: false,
            backgroundCaptureIsEnabled: true))
    }
}
