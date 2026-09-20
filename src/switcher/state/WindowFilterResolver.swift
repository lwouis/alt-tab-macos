import Foundation

/// Decides whether a single window is shown to the user in the switcher, given the per-shortcut
/// filter preferences and the surrounding context. Pure kernel: takes the window's `WindowState`,
/// the app's `ApplicationState`, the dropdown booleans (defaulted to `false` so tests only spell out
/// what they exercise), the runtime context (frontmost pid, visible spaces, exceptions), and a
/// **lazy** `isOnPreferredScreen` — the one fact that's irreducibly OS-coupled (`Window.isOnScreen`
/// touches `Spaces.screenSpacesMap` + multi-screen quartz math) — and a **lazy** `isUnderCursor` (the
/// window's frame against the cursor, which `WindowState` doesn't carry). Everything else is a pure
/// expression over the inputs, evaluated inline so `&&` short-circuits exactly like the original.
enum WindowFilterResolver {
    /// True iff the window passes every active filter. Mirrors the original predicate term-for-term;
    /// `isOnPreferredScreen` is an `@autoclosure` so the (relatively expensive) OS call only fires
    /// when the short-circuit reaches it — phantom / hidden / windowless windows never trigger it.
    static func shouldShow(_ s: WindowState, _ app: ApplicationState,
                           onlyFrontmostApp: Bool = false,       // appsToShow == .active
                           excludeFrontmostApp: Bool = false,    // appsToShow == .nonActive
                           onlyUnderCursor: Bool = false,        // appsToShow == .underCursor
                           hideHidden: Bool = false,             // showHiddenWindows == .hide
                           hideWindowless: Bool = false,         // showWindowlessApps == .hide
                           hideFullscreen: Bool = false,         // showFullscreenWindows == .hide
                           hideMinimized: Bool = false,          // showMinimizedWindows == .hide
                           onlyVisibleSpaces: Bool = false,      // spacesToShow == .visible
                           onlyNonVisibleSpaces: Bool = false,   // spacesToShow == .nonVisible
                           onlyPreferredScreen: Bool = false,    // screensToShow == .showingAltTab
                           separateTabs: Bool = false,           // groupTabs == .separateWindows
                           frontmostPid: pid_t? = nil,
                           visibleSpaceIds: [UInt64] = [],       // CGSSpaceID === UInt64
                           exceptions: [ExceptionEntry] = [],
                           isOnPreferredScreen: @autoclosure () -> Bool,
                           isUnderCursor: @autoclosure () -> Bool = false) -> Bool {
        !s.isPhantom &&
            !ExceptionMatcher.hidesWindow(s, app, exceptions: exceptions,
                activeAppOverride: onlyFrontmostApp && frontmostPid == app.pid) &&
            !(onlyFrontmostApp && !(frontmostPid == app.pid)) &&
            !(excludeFrontmostApp && frontmostPid == app.pid) &&
            !(hideHidden && app.isHidden) &&
            ((!hideWindowless && !onlyUnderCursor && s.isWindowlessApp) ||
                !s.isWindowlessApp &&
                !(hideFullscreen && s.isFullscreen) &&
                !(hideMinimized && s.isMinimized) &&
                // A held tab (kept visible through the new-tab discovery gap) just backgrounded on the
                // CURRENT visible Space, so it is Space-less yet belongs on-screen. `isPhantom` already
                // exempts it, but these Space/screen gates are SEPARATE and would still hide it — the exact
                // vanish that defeated the hold on the FIRST tab of a window, where no group exists yet to
                // borrow it a Space (live capture 2026-07-24: `(h)…sp[]` dumped with a `-` prefix). Treat
                // held as "on the visible Space and preferred screen": shows under `.visible`, hidden under
                // `.nonVisible`, and never dropped by the preferred-screen gate.
                !(onlyVisibleSpaces && !s.isHeldVisibleForTab && !inAnyVisibleSpace(s, visibleSpaceIds)) &&
                !(onlyNonVisibleSpaces && (s.isHeldVisibleForTab || inAnyVisibleSpace(s, visibleSpaceIds))) &&
                !(onlyPreferredScreen && !s.isHeldVisibleForTab && !isOnPreferredScreen()) &&
                (separateTabs || !s.isTabbed) &&
                // A minimized window, a hidden app's window, or a window on another Space still has a stored
                // frame that may contain the cursor, but nothing is drawn there: only what is actually under
                // the pointer qualifies. Windowless placeholders are excluded above for the same reason.
                !(onlyUnderCursor && (s.isMinimized || app.isHidden || !isOnVisibleSpace(s, visibleSpaceIds) || !isUnderCursor())))
    }

    /// A held tab counts as on the visible Space (see the Space gates above).
    private static func isOnVisibleSpace(_ s: WindowState, _ visibleSpaceIds: [UInt64]) -> Bool {
        s.isHeldVisibleForTab || inAnyVisibleSpace(s, visibleSpaceIds)
    }

    private static func inAnyVisibleSpace(_ s: WindowState, _ visibleSpaceIds: [UInt64]) -> Bool {
        visibleSpaceIds.contains { visibleSpace in s.spaceIds.contains { $0 == visibleSpace } }
    }
}
