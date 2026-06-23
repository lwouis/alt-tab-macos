import XCTest

/// Pins the WindowServer field decode against the exact bit/mask values observed on macOS 26 (diffing a
/// window across normal / minimized / fullscreen states). If a future macOS shifts these, this fails loudly
/// instead of silently mis-classifying windows.
final class WsWindowStateTests: XCTestCase {
    private func raw(attributes: UInt64 = 0x3, level: Int32 = 0, spaceTypeMask: UInt64 = 0x1) -> WsRawWindow {
        WsRawWindow(wid: 42, pid: 7,
                    attributes: attributes, level: level, spaceTypeMask: spaceTypeMask, title: "x")
    }

    // MARK: - A. Ordered-in / on-screen (NOT a minimized signal — minimized comes from AX kAXMinimized)

    func testVisibleWhenAttributeBitSet() {
        let w = raw(attributes: 0x3) // observed: normal on-screen standard window
        XCTAssertTrue(WsWindowState.isVisible(w))
    }

    func testNotVisibleWhenAttributeBitClear() {
        let w = raw(attributes: 0x1) // observed: same window after it ordered out (minimize / hide / close)
        XCTAssertFalse(WsWindowState.isVisible(w))
    }

    // MARK: - B. Fullscreen

    func testFullscreenWhenSpaceMaskBitSet() {
        XCTAssertTrue(WsWindowState.isFullscreen(raw(spaceTypeMask: 0x20))) // observed: fullscreen Space
    }

    func testNotFullscreenOnNormalSpace() {
        XCTAssertFalse(WsWindowState.isFullscreen(raw(spaceTypeMask: 0x1))) // observed: normal Space
    }

    // MARK: - C. Application-window level hint

    func testApplicationWindowAtLevelZero() {
        XCTAssertTrue(WsWindowState.isApplicationWindowLevel(raw(level: 0)))
    }

    func testChromeAndPanelsAreNotApplicationLevel() {
        for level: Int32 in [3 /* floating panel */, 24 /* menu bar */, 25 /* Control Center */, 2147483630 /* status indicator */] {
            XCTAssertFalse(WsWindowState.isApplicationWindowLevel(raw(level: level)), "level \(level) is chrome, not an app window")
        }
    }
}
