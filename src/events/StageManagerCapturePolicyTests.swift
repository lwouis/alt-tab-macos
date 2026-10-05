import XCTest

final class StageManagerCapturePolicyTests: XCTestCase {
    private let size = CGSize(width: 1000, height: 800)

    func testSidebarGeometryIsRejectedEvenWhenCaptureOutputIsRescaled() {
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 180, height: 120), size))
        XCTAssertTrue(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: size), size))
    }

    func testEitherCompressedAxisIsRejectedAndExactNinetyPercentIsAccepted() {
        for bounds in [CGRect(x: 0, y: 0, width: 850, height: 800),
                       CGRect(x: 0, y: 0, width: 1000, height: 680),
                       CGRect(x: 0, y: 0, width: 899, height: 800),
                       CGRect(x: 0, y: 0, width: 1000, height: 719)] {
            XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(bounds, size))
        }
        XCTAssertTrue(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 900, height: 720), size))
        XCTAssertTrue(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: size), size))
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 66, height: 98), CGSize(width: 80, height: 92)))
    }

    func testUnknownGeometryDoesNotOverwriteLastGoodFrame() {
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(nil, size))
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(.zero, size))
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: size), .zero))
    }

    func testNonFiniteGeometryDoesNotOverwriteLastGoodFrame() {
        let normal = CGRect(origin: .zero, size: size)
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            for invalidSize in [CGSize(width: invalid, height: size.height), CGSize(width: size.width, height: invalid)] {
                XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: invalidSize), size))
                XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(normal, invalidSize))
            }
        }
    }

    func testCaptureFromBeforeOffOnToggleCannotPublishInNewMode() {
        var mode = StageManagerCaptureMode()
        mode.update(true)
        let captureMode = mode
        mode.update(false)
        mode.update(true)
        XCTAssertNotEqual(captureMode, mode)
        XCTAssertTrue(mode.enabled)
    }

    func testProtectedCaptureCannotPublishAfterWindowLostFocusAndReturned() {
        var mode = StageManagerCaptureMode()
        mode.update(true)
        XCTAssertFalse(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 3, isFocused: true))
        XCTAssertFalse(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 1, isFocused: false))
        XCTAssertTrue(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 1, isFocused: true))
    }

    func testProtectionOffPreservesBackgroundCaptureBehavior() {
        let mode = StageManagerCaptureMode()
        XCTAssertTrue(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 3, isFocused: false))
    }

    func testUnchangedModeKeepsQueuedCapturesValid() {
        var mode = StageManagerCaptureMode()
        let captureMode = mode
        mode.update(false)
        XCTAssertEqual(captureMode, mode)
        mode.update(true)
        let protectedCaptureMode = mode
        mode.update(true)
        XCTAssertEqual(protectedCaptureMode, mode)
    }
}
