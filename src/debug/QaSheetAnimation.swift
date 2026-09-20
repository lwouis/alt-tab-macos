#if DEBUG
import Cocoa
import ObjectiveC.runtime

// AppKit's sheet presentation is a quarter of a second, and it is spent on the MAIN THREAD: `beginSheet`
// returns ~275ms after it was called, and `endSheet` ~270ms, measured on macOS 27 (2026-09-19). Nothing
// public shortens it: `animationBehavior = .none` on either window, an `NSAnimationContext` of duration 0
// around the call, and `NSAutomaticWindowAnimationsEnabled` in the argument domain all leave the same 275ms,
// spent once per sheet per look and per license: a quarter of VR-01's run (107.8s -> 81.3s without it).
//
// `-[NSWindow _setDisableSheetAnimation:]` is what actually turns it off: 275ms becomes 12ms to show and 3ms
// to put away, and the pictures come out byte for byte what they were with the animation on. It is private,
// so it is asked for by name and skipped when it is not there. A macOS that drops it photographs the same
// pictures, just at the old speed.
enum QaSheetAnimation {
    private static let selector = NSSelectorFromString("_setDisableSheetAnimation:")

    /// Set on the SHEET, before it is begun: the parent window's flag does nothing. It stays with the window,
    /// so the same sheet closes without animating either.
    static func disable(on sheet: NSWindow?) {
        guard Preferences.qaPristine, let sheet, sheet.responds(to: selector),
              let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(method_getImplementation(method), to: Setter.self)(sheet, selector, true)
    }
}
#endif
