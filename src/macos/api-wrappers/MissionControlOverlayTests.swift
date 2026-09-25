import XCTest

final class MissionControlOverlayTests: XCTestCase {
    private let screen = CGSize(width: 2560, height: 1440)

    private func wm(_ layer: Int, _ bounds: CGRect) -> MissionControlOverlay.Surface {
        MissionControlOverlay.Surface(ownerName: MissionControlOverlay.windowManagerProcessName, layer: layer, bounds: bounds)
    }

    private func fullScreen(_ layer: Int) -> MissionControlOverlay.Surface {
        wm(layer, CGRect(origin: .zero, size: screen))
    }

    private func gesture(_ surfaces: [MissionControlOverlay.Surface]) -> MissionControlOverlay.Gesture {
        MissionControlOverlay.gesture(surfaces, screenSizes: [screen])
    }

    func testNothingUpIsNoGesture() {
        XCTAssertEqual(gesture([fullScreen(0)]), MissionControlOverlay.Gesture.none)
    }

    func testFullScreenShieldIsAppExpose() {
        XCTAssertEqual(gesture([fullScreen(MissionControlOverlay.exposeShieldLevel)]), .appExpose)
    }

    func testShieldWithSpacesBarIsMissionControl() {
        let bar = wm(MissionControlOverlay.spacesBarLevel, CGRect(x: 0, y: 0, width: 2560, height: 120))
        XCTAssertEqual(gesture([fullScreen(MissionControlOverlay.exposeShieldLevel), bar]), .missionControl)
    }

    func testShowDesktopOverlayIsShowDesktop() {
        XCTAssertEqual(gesture([fullScreen(MissionControlOverlay.showDesktopOverlayLevel)]), .showDesktop)
    }

    func testSmallSurfaceAtShieldLevelIsNotAGesture() {
        let observed = wm(MissionControlOverlay.exposeShieldLevel, CGRect(x: 2823, y: 771, width: 66, height: 82))
        XCTAssertEqual(gesture([observed]), MissionControlOverlay.Gesture.none)
    }

    func testShieldMatchesAnyScreenSize() {
        let small = CGSize(width: 1512, height: 982)
        let shield = wm(MissionControlOverlay.exposeShieldLevel, CGRect(x: 2560, y: 0, width: small.width, height: small.height))
        XCTAssertEqual(MissionControlOverlay.gesture([shield], screenSizes: [screen, small]), .appExpose)
    }

    func testOtherOwnersAtShieldLevelAreIgnored() {
        let other = MissionControlOverlay.Surface(ownerName: "SomeApp", layer: MissionControlOverlay.exposeShieldLevel,
            bounds: CGRect(origin: .zero, size: screen))
        XCTAssertEqual(gesture([other]), MissionControlOverlay.Gesture.none)
    }

    func testShieldWithoutBoundsIsNotAGesture() {
        let shield = MissionControlOverlay.Surface(ownerName: MissionControlOverlay.windowManagerProcessName,
            layer: MissionControlOverlay.exposeShieldLevel, bounds: nil)
        XCTAssertEqual(gesture([shield]), MissionControlOverlay.Gesture.none)
    }
}
