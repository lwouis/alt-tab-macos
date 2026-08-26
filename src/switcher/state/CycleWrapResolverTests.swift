import XCTest

final class CycleWrapResolverTests: XCTestCase {
    private func advance(wrapping: Bool = true, allowWrap: Bool = true,
                         lastEventIsARepeat: Bool = false,
                         isArtificialRepeatTick: Bool = false) -> CycleAdvance {
        return CycleAdvance(isWrapping: wrapping, allowWrap: allowWrap,
                            lastEventIsARepeat: lastEventIsARepeat,
                            isArtificialRepeatTick: isArtificialRepeatTick)
    }

    // The bug. `previousWindowShortcut` defaults to the modifier-only ⇧, so it stays `.down` — and its
    // artificial-repeat timer stays ARMED — for as long as the user holds ⇧. A ⌥⇧+⇥ press landing during
    // that hold is a discrete user press, not a repeat, so it must wrap exactly as a forward ⌥+⇥ tap does.
    // Armed-ness is a fact about the session; being a repeat is a fact about THIS advance.
    func testADiscretePressWrapsWhileAHeldModifierKeepsTheRepeatTimerArmed() {
        XCTAssertFalse(CycleWrapResolver.blocksWrap(advance()))
    }

    // Intent that must survive the fix: holding the key walks to the end and STOPS, rather than looping
    // forever under the user's fingers.
    func testASynthesizedRepeatStopsAtTheEndInsteadOfWrapping() {
        XCTAssertTrue(CycleWrapResolver.blocksWrap(advance(isArtificialRepeatTick: true)))
    }

    func testAnOsKeyRepeatStopsAtTheEndInsteadOfWrapping() {
        XCTAssertTrue(CycleWrapResolver.blocksWrap(advance(lastEventIsARepeat: true)))
    }

    func testAnAdvanceThatDoesNotReachTheEndIsNeverBlocked() {
        XCTAssertFalse(CycleWrapResolver.blocksWrap(advance(wrapping: false, lastEventIsARepeat: true)))
        XCTAssertFalse(CycleWrapResolver.blocksWrap(advance(wrapping: false, isArtificialRepeatTick: true)))
        XCTAssertFalse(CycleWrapResolver.blocksWrap(advance(wrapping: false, allowWrap: false)))
    }

    func testWrapIsRefusedWhenTheCallerForbidsIt() {
        XCTAssertTrue(CycleWrapResolver.blocksWrap(advance(allowWrap: false)))
    }
}
