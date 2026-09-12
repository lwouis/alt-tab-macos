import Cocoa

/// Pure kernel for `AXUIElement.windowsIncludingKeyAndMain`: which attributes one batched AX read on an
/// application element must ask for, and how to fold the three answers into one list of window elements.
/// `WindowElementAcquisition` matches that list by wid and brute-forces only what is left.
///
/// **Why three attributes and not just `kAXWindows`.** AppKit builds `kAXWindows` from a single
/// `windowsWithOptions:onSpaces:forConnectionID:` query restricted to `currentManagedSpaces`, which is the
/// entire reason other-Space windows are missing from it. `kAXFocusedWindow` and `kAXMainWindow` are instead
/// a bare `objc_loadWeak` of `NSApplication._keyWindow` / `._mainWindow`: no Space query, and no `isActive`
/// guard either — unlike the public `NSApp.keyWindow`, which returns nil for a background app and is why this
/// looks like it cannot work. So a background app whose windows all sit on another Space still hands back its
/// last key window here, as a genuine `AXWindow` root with the right wid (measured on macOS 26.6.2). That is
/// one other-Space window per app the brute-force sweep never has to search for.
enum PublishedWindows {
    /// Asked for together, because `AXUIElementCopyMultipleAttributeValues` batches them into ONE round trip:
    /// the two unfiltered attributes cost no IPC over reading `kAXWindows` alone. Dropping either back out of
    /// this list silently gives up every other-Space window they were reaching, with no test going red
    /// anywhere but here.
    static let attributes = [kAXWindowsAttribute, kAXFocusedWindowAttribute, kAXMainWindowAttribute]

    /// `windows` is nil when the app did not answer that attribute, and can repeat an element (macOS bug:
    /// Mail at login returns duplicates). `focused` / `main` are nil for an app implementing neither, and are
    /// usually the same element as each other and as one of `windows`.
    ///
    /// **An empty `kAXWindows` is not an empty answer.** An app with every window on another Space answers
    /// `[]` there and still names its key window, so returning early on an empty array would throw away the
    /// only case this kernel exists for.
    static func merge<Element: Hashable>(windows: [Element]?, focused: Element?, main: Element?) -> [Element] {
        var seen = Set<Element>()
        var result = [Element]()
        for element in (windows ?? []) + [focused, main].compactMap({ $0 }) {
            guard seen.insert(element).inserted else { continue }
            result.append(element)
        }
        return result
    }
}
