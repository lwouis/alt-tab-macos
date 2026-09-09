import Cocoa

/// What one `AXTitleChanged` delivery is worth, once the element carrying it has been asked what it is.
enum AxTitleVerdict: Equatable {
    /// the window renamed itself; this is the string to record
    case apply(String)
    /// something INSIDE the window renamed itself, which says nothing about the window's own title
    case ignoreNotTheWindow
    /// the window's element answered no title at all
    case ignoreNoTitle
}

/// **Whose name is in an `AXTitleChanged`.**
///
/// The subscription is taken on the APPLICATION element, so a delivery can name any element of the app, and
/// `_AXUIElementGetWindow` answers with the CONTAINING window's id for a descendant. A wid therefore says
/// which window the element sits in, never that the element IS the window. `BruteForceWindowMatch
/// .isTargetWindowRoot` pays a role read against the same fact before a scan accepts a candidate, and
/// `Applications.applyObservedElement` before it adopts one.
///
/// Recording a descendant's `kAXTitle` as its window's is what listed a Chromium window as "Chromium"
/// (#6011): the node's own title is empty, and `Window.bestEffortTitle` resolves an empty title to the app
/// name once the WindowServer has no title either, which is the case for every app that draws its own title
/// bar.
enum AxTitleNotificationPolicy {
    /// The role decides before the string does: a descendant is refused even when its title looks perfectly
    /// usable, because a plausible string from the wrong element is the harder bug to see.
    ///
    /// An EMPTY title from the window itself is applied, not ignored. The window really has no title then,
    /// and choosing what to show for that is `Window.bestEffortTitle`'s job (the WindowServer's title, then
    /// the app name), not this one's.
    static func verdict(role: String?, title: String?) -> AxTitleVerdict {
        guard role == kAXWindowRole else { return .ignoreNotTheWindow }
        guard let title else { return .ignoreNoTitle }
        return .apply(title)
    }
}
