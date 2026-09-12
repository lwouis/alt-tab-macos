import XCTest

/// Pins the WindowServer field decode against the exact bit/mask values observed on macOS 26 (diffing a
/// window across normal / minimized / fullscreen states). If a future macOS shifts these, this fails loudly
/// instead of silently mis-classifying windows.
final class WsWindowStateTests: XCTestCase {
    private func raw(attributes: UInt64 = 0x3, level: Int32 = 0, spaceTypeMask: UInt64 = 0x1,
                     tags: UInt64 = 0x0300000100482001) -> WsRawWindow {
        WsRawWindow(wid: 42, pid: 7,
                    attributes: attributes, level: level, spaceTypeMask: spaceTypeMask, title: "x",
                    tags: tags)
    }

    // MARK: - A. Ordered-in / on-screen (NOT a minimized signal — that is `tags` bit 60, section D)

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

    func testParentDefaultsToIndependentRoot() {
        XCTAssertEqual(raw().parentWid, 0)
    }

    func testAlphaDefaultsToOpaque() {
        XCTAssertEqual(raw().alpha, 1)
    }

    // MARK: - D. Minimized (the observed `tags` values — see WsWindowStateSpecs.md for the full matrix)

    func testMinimizedWhenTagBitSet() {
        XCTAssertTrue(WsWindowState.isMinimized(raw(tags: 0x1300000100480001)))
    }

    func testNotMinimizedWhenTagBitClear() {
        XCTAssertFalse(WsWindowState.isMinimized(raw(tags: 0x0300000100482001)))
    }

    /// The discrimination the whole change rests on: an `orderOut:` window (#5714) and a Space-less
    /// background tab both read this value — ordered OUT, but not minimized. Reading the ordered-out bit as
    /// "minimized" is exactly the conflation that kept minimized on AX for so long.
    func testOrderedOutWindowIsNotMinimized() {
        XCTAssertFalse(WsWindowState.isMinimized(raw(tags: 0x0300000100480001)))
    }

    func testFullscreenWindowIsNotMinimized() {
        XCTAssertFalse(WsWindowState.isMinimized(raw(tags: 0x0300048100082401)))
    }

    func testHiddenAppsWindowIsNotMinimized() {
        XCTAssertFalse(WsWindowState.isMinimized(raw(tags: 0x0300008100480001)))
    }

    /// Minimized and app-hidden are independent bits, so a minimized window inside a hidden app carries both.
    func testHiddenAndMinimizedComposes() {
        XCTAssertTrue(WsWindowState.isMinimized(raw(tags: 0x1300008100480001)))
    }
}
