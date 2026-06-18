import XCTest

final class WindowCaptureMethodResolverTests: XCTestCase {
    func testMacOS14UsesScreenCaptureKitWhenStageManagerIsOff() {
        XCTAssertEqual(WindowCaptureMethodResolver.method(osMajorVersion: 14, stageManagerEnabled: false), .screenCaptureKit)
    }

    func testMacOS15UsesPrivateApiBecauseScreenCaptureKitIsBuggy() {
        XCTAssertEqual(WindowCaptureMethodResolver.method(osMajorVersion: 15, stageManagerEnabled: false), .privateApi)
    }

    func testOlderMacOSUsesPrivateApi() {
        XCTAssertEqual(WindowCaptureMethodResolver.method(osMajorVersion: 13, stageManagerEnabled: false), .privateApi)
    }

    func testStageManagerUsesPrivateApiEvenOnScreenCaptureKitOSVersions() {
        XCTAssertEqual(WindowCaptureMethodResolver.method(osMajorVersion: 14, stageManagerEnabled: true), .privateApi)
        XCTAssertEqual(WindowCaptureMethodResolver.method(osMajorVersion: 26, stageManagerEnabled: true), .privateApi)
    }

    func testStageManagerReadsWindowManagerGlobalFlag() {
        let suiteName = "test-window-manager-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(StageManager.isEnabled(defaults: defaults))

        defaults.set(true, forKey: "GloballyEnabled")

        XCTAssertTrue(StageManager.isEnabled(defaults: defaults))
    }
}
