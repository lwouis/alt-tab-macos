import XCTest
import Cocoa

final class OnActionExtensionTests: XCTestCase {

    // MARK: - Getter round-trip

    func testGetterReturnsNilWhenUnset() {
        let control = NSControl()
        XCTAssertNil(control.onAction)
    }

    func testGetterReturnsClosureAfterSet() {
        let control = NSControl()
        control.onAction = { _ in }
        XCTAssertNotNil(control.onAction,
            "regression: getter must return the stored closure so wrap patterns can chain")
    }

    func testGetterReturnsSameClosureThatSetterStored() {
        let control = NSControl()
        var calls = 0
        control.onAction = { _ in calls += 1 }
        control.onAction?(control)
        XCTAssertEqual(calls, 1)
    }

    // MARK: - Target/action plumbing

    func testSetterConfiguresTargetAndAction() {
        let control = NSControl()
        control.onAction = { _ in }
        XCTAssertNotNil(control.target)
        XCTAssertNotNil(control.action)
    }

    func testSetterReplacesPreviousClosure() {
        let control = NSControl()
        var firstCalls = 0
        var secondCalls = 0
        control.onAction = { _ in firstCalls += 1 }
        control.onAction = { _ in secondCalls += 1 }
        control.onAction?(control)
        XCTAssertEqual(firstCalls, 0, "old closure should not fire after a new one is set")
        XCTAssertEqual(secondCalls, 1)
    }

    /// AppKit invokes the wired action via the target/action pair, NOT by calling the stored
    /// closure directly. The other tests exercise the getter path (`control.onAction?(c)`); this
    /// pins the `SelectorWrapper.callClosure` indirection that is what AppKit actually triggers
    /// when a click hits the control.
    func testActionFiresClosureViaTargetActionPlumbing() {
        let control = NSControl()
        var calls = 0
        var receivedSender: AnyObject? = nil
        control.onAction = { sender in
            calls += 1
            receivedSender = sender
        }
        // AppKit's real call site is `[target performSelector:action with:sender]`. Using
        // perform(_:with:) here matches what the runtime does, going through SelectorWrapper.
        _ = control.target?.perform(control.action!, with: control)
        XCTAssertEqual(calls, 1,
            "SelectorWrapper.callClosure must forward the target/action invocation to the stored closure.")
        XCTAssertTrue(receivedSender === control,
            "The sender forwarded to the closure must be the control AppKit invoked the action on.")
    }

    func testSettingNilClearsTargetAndAction() {
        let control = NSControl()
        control.onAction = { _ in }
        control.onAction = nil
        XCTAssertNil(control.target)
        XCTAssertNil(control.action)
        XCTAssertNil(control.onAction)
    }

    // MARK: - Wrap pattern (the AppearanceTab use case)

    /// AppearanceTab reads `let original = control.onAction` and writes a new onAction that falls
    /// through to `original?(control)`. This is the exact shape that was broken.
    func testWrapPatternInvokesPreviousClosureOnFallthrough() {
        let control = NSControl()
        var originalCalls = 0
        var wrapperCalls = 0

        control.onAction = { _ in originalCalls += 1 }
        let original = control.onAction
        XCTAssertNotNil(original,
            "regression: without the getter fix, `original` would be nil and the wrap would orphan the underlying action")

        control.onAction = { c in
            wrapperCalls += 1
            original?(c)
        }

        control.onAction?(control)
        XCTAssertEqual(wrapperCalls, 1)
        XCTAssertEqual(originalCalls, 1,
            "regression: the wrapper must be able to call through to the previously-set closure")
    }

    /// When the wrap returns early (the Pro-click branch), the original closure must NOT fire —
    /// otherwise `controlWasChanged` would still write the Pro value to `Preferences`.
    func testWrapPatternSkipsPreviousClosureOnEarlyReturn() {
        let control = NSControl()
        var originalCalls = 0
        control.onAction = { _ in originalCalls += 1 }
        let original = control.onAction

        control.onAction = { _ in
            // simulate the "isProLocked + isProSegment" branch: do side effect, return early
            // original?(c) is NOT called here
        }
        _ = original

        control.onAction?(control)
        XCTAssertEqual(originalCalls, 0,
            "original closure must not fire when the wrap returns early")
    }

    /// The closure captured in `original` must survive even after the wrap overwrites the
    /// associated object. Without strong capture semantics, this would no-op.
    func testOriginalClosureSurvivesReassignment() {
        let control = NSControl()
        var calls = 0
        control.onAction = { _ in calls += 1 }
        let original = control.onAction

        // simulate many reassignments to provoke any premature release
        for _ in 0..<10 {
            control.onAction = { _ in }
        }

        original?(control)
        XCTAssertEqual(calls, 1)
    }
}
