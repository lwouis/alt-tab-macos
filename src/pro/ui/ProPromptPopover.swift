import Cocoa

/// Shared plumbing for the Pro-transition menubar-anchored popovers ([B] Day 12 Heads-Up,
/// [E] Day 15 Hard Gate, [F] Day 21 Reminder, [H] Day 4 Tour). Centralises construction
/// (transient behavior, optional fixed content size) and presentation (activate app, anchor
/// below the menubar icon, make the popover window key).
enum ProPromptPopover {
    /// Build a transient popover ready for the caller to fill with content. A fixed content
    /// size is optional — omit for views that are auto-sized via constraints.
    static func make(contentSize: NSSize? = nil) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        if let contentSize { popover.contentSize = contentSize }
        return popover
    }

    /// Anchor the popover below the menubar icon and make its content window key.
    static func present(_ popover: NSPopover, content: NSView) {
        let vc = NSViewController()
        vc.view = content
        popover.contentViewController = vc
        App.shared.activate(ignoringOtherApps: true)
        Menubar.showPopoverFromMenubar(popover)
        popover.contentViewController?.view.window?.makeKey()
    }
}
