import Cocoa

class TabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let tabViewItem = tabViewItem, let window = view.window else { return }
        window.title = tabViewItem.label
        resizeWindowToFit(tabViewItem, window)
    }

    private func resizeWindowToFit(_ tabViewItem: NSTabViewItem, _ window: NSWindow) {
        let contentFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: tabViewItem.view!.frame.size))
        let toolbarHeight = window.frame.size.height - contentFrame.size.height
        let newOrigin = NSPoint(x: window.frame.origin.x, y: window.frame.origin.y + toolbarHeight)
        let newFrame = NSRect(origin: newOrigin, size: contentFrame.size)
        window.setFrame(newFrame, display: false, animate: true)
    }
}