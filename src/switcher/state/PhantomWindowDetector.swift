import Foundation

/// Detects whether a window is a "phantom": present in macOS APIs (AX hands it back with a valid
/// `CGWindowID`) but not something the app actually means to show the user — alpha=0 Outlook reminders,
/// `orderOut:` / `show:false` Electron windows, WeChat/Teams hidden windows, etc. The pixel content may
/// be absent, black, or anything; what matters is that AltTab shouldn't offer it as a switch target. See
/// `src/experimentations/PhantomWindowDetection.swift` for the full investigation.
///
/// Pure kernel over the test-constructible `WindowState` + `ApplicationState` records (no SkyLight, no
/// `@testable`). Two entry points, by how much CGS data the caller has — they share the same notion of
/// "phantom" but the synchronous one can only observe the *strong* signal:
enum PhantomWindowDetector {
    /// Synchronous, cheap — runs on every show (`Window.recomputeIsPhantom`). Knows only the STRONG
    /// signal: the window has no Space at all (CGS lost track of it — Joplin / Sprig / `show:false`
    /// Electron). ASSERT-ONLY: it may raise `isPhantom`, never clear it. Non-empty `spaceIds` is NOT
    /// proof of visibility — a weak-signal phantom (alpha=0 / `orderOut:` still on a Space) keeps its
    /// Space, and that's only observable via the off-main CGS query in `cgsVerdict`. Clearing here would
    /// clobber `cgsVerdict`'s verdict on every show, so the phantom reappears on every summon (#5714).
    /// Reads the current verdict from `s.isPhantom`, so it's monotonic within the synchronous path.
    static func syncVerdict(_ s: WindowState, _ app: ApplicationState) -> Bool {
        s.isPhantom || (s.spaceIds.isEmpty && !s.isTabbed && !s.isMinimized && !app.isHidden)
    }

    /// Authoritative — runs ~250ms post-show off-main (`Applications.refreshIsPhantom`) with the two CGS
    /// window lists (`inVisibleList` excludes the `.invisible1/.invisible2` tags, `inAllList` includes
    /// them). Knows BOTH the strong and weak signals; owns the full verdict, including clearing.
    /// Disambiguation order matches `PhantomWindowDetection.swift`.
    static func cgsVerdict(_ s: WindowState, _ app: ApplicationState,
                           inVisibleList: Bool, inAllList: Bool, visibleSpaceIds: [UInt64]) -> Bool {
        // strong signal: CGS dropped the WID from every Space
        if !inAllList { return true }
        // tagged invisible by CGS — disambiguate against the legitimate reasons a window lives there
        if inVisibleList { return false }
        if s.isMinimized || app.isHidden || s.isTabbed { return false }
        // known Spaces, none of them visible → legitimate other-Space window
        if !s.spaceIds.isEmpty && !s.spaceIds.contains(where: { visibleSpaceIds.contains($0) }) { return false }
        // weak signal: alpha=0 / orderOut: window still on a visible Space
        return true
    }
}
