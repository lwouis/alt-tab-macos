import Foundation

/// Matches windows/apps against the user's exception rules. Two independent, pure questions:
///   • `hidesWindow` — should this window be hidden from the switcher? (the exception's `hide` rule)
///   • `disablesShortcuts` — should AltTab's global shortcuts be turned off while this app is
///     frontmost? (the exception's `ignore` rule)
/// Both share a **bundle-id prefix gate**: an exception applies iff its `bundleIdentifier` is non-empty
/// and the app's bundle id has it as a prefix. Operates on canonical `WindowState` / `ApplicationState`
/// records — no `Window`/`Application` references, so it tests with plain data.
enum ExceptionMatcher {
    /// An exception applies to a window iff its bundle-id prefix matches the window's app and its
    /// `hide` rule fires. nil bundle-id never matches.
    ///
    /// `activeAppOverride` is set when the filter is "Active app" and this window's app is the active
    /// one (#5810): the user asked to see this app's windows, which is a stronger intent than the
    /// Exceptions list, so the blanket `.always` / `.whenNoOpenWindow` hide rules are ignored. The
    /// narrower `.windowTitleContains` rule still fires, since it only hides *some* windows.
    static func hidesWindow(_ s: WindowState, _ app: ApplicationState, exceptions: [ExceptionEntry],
                            activeAppOverride: Bool = false) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return exceptions.contains { e in
            !e.bundleIdentifier.isEmpty && id.hasPrefix(e.bundleIdentifier) && hideMatches(e, s, activeAppOverride: activeAppOverride)
        }
    }

    static func hideMatches(_ e: ExceptionEntry, _ s: WindowState, activeAppOverride: Bool = false) -> Bool {
        switch e.hide {
            case .none: return false
            case .always: return !activeAppOverride
            case .whenNoOpenWindow: return !activeAppOverride && s.isWindowlessApp
            case .windowTitleContains:
                guard let patterns = e.windowTitleContains, !patterns.isEmpty else { return false }
                return patterns.contains { !$0.isEmpty && s.title.contains($0) }
        }
    }

    /// Shortcuts are disabled while an app is frontmost iff a matching exception's `ignore` rule fires:
    /// `.always`, or `.whenFullscreen` while the active window is fullscreen. nil bundle-id never matches.
    static func disablesShortcuts(_ app: ApplicationState, isFullscreen: Bool, exceptions: [ExceptionEntry]) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return exceptions.contains { e in
            !e.bundleIdentifier.isEmpty && id.hasPrefix(e.bundleIdentifier) &&
                (e.ignore == .always || (e.ignore == .whenFullscreen && isFullscreen))
        }
    }
}
