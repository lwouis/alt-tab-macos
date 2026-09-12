import XCTest

final class WindowServerCaptureFallbackTests: XCTestCase {
    func testQueuedCaptureChecksCurrentEligibility() {
        var isEligible = true
        var captures = 0
        let queuedCapture = {
            WindowServerCaptureFallback.capture(
                if: { isEligible },
                primary: { captures += 1; return "primary" },
                fallback: { captures += 1; return "fallback" }
            )
        }
        isEligible = false
        XCTAssertNil(queuedCapture())
        XCTAssertEqual(captures, 0)
    }

    func testFallbackRechecksEligibilityAfterPrimaryReturns() {
        var isEligible = true
        var fallbackCalls = 0
        let image = WindowServerCaptureFallback.capture(
            if: { isEligible },
            primary: { isEligible = false; return nil as String? },
            fallback: { fallbackCalls += 1; return "fallback" }
        )
        XCTAssertNil(image)
        XCTAssertEqual(fallbackCalls, 0)
    }
}
