import Cocoa
import XCTest

final class WindowAcquisitionPolicyTests: XCTestCase {
    private func observation(_ wid: CGWindowID?, _ role: String?) -> WindowAcquisitionPolicy.ApplicationWindowObservation {
        WindowAcquisitionPolicy.ApplicationWindowObservation(wid: wid, role: role)
    }

    func testApplicationElementWithZeroWidIsMalformed() {
        XCTAssertTrue(WindowAcquisitionPolicy.applicationWindowsAreMalformed([observation(0, kAXApplicationRole)]))
    }

    func testHealthyWindowIsNotMalformed() {
        XCTAssertFalse(WindowAcquisitionPolicy.applicationWindowsAreMalformed([observation(42, kAXWindowRole)]))
    }

    func testOrdinaryMissIsNotMalformed() {
        XCTAssertFalse(WindowAcquisitionPolicy.applicationWindowsAreMalformed([]))
    }

    func testZeroWidWithoutApplicationRoleIsNotMalformed() {
        XCTAssertFalse(WindowAcquisitionPolicy.applicationWindowsAreMalformed([observation(0, nil)]))
    }

    func testApplicationRoleWithRealWidIsNotMalformed() {
        XCTAssertFalse(WindowAcquisitionPolicy.applicationWindowsAreMalformed([observation(42, kAXApplicationRole)]))
    }

    func testNormalWindowServerCandidateIsEligibleForFallback() {
        XCTAssertTrue(WindowAcquisitionPolicy.windowServerFallbackIsEligible(wid: 42, level: 0, size: CGSize(width: 800, height: 600)))
    }

    func testFallbackRejectsMissingIdentityChromeAndSmallSurfaces() {
        XCTAssertFalse(WindowAcquisitionPolicy.windowServerFallbackIsEligible(wid: 0, level: 0, size: CGSize(width: 800, height: 600)))
        XCTAssertFalse(WindowAcquisitionPolicy.windowServerFallbackIsEligible(wid: 42, level: 3, size: CGSize(width: 800, height: 600)))
        XCTAssertFalse(WindowAcquisitionPolicy.windowServerFallbackIsEligible(wid: 42, level: 0, size: CGSize(width: 100, height: 600)))
        XCTAssertFalse(WindowAcquisitionPolicy.windowServerFallbackIsEligible(wid: 42, level: 0, size: CGSize(width: 800, height: 50)))
    }
}
