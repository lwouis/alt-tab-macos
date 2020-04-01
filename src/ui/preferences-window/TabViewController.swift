import Cocoa

class TabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let tabViewItem = tabViewItem, let window = view.window else { return }
        window.title = tabViewItem.label
        resizeWindowToFit(tabViewItem, window)
    }

    private func resizeWindowToFit(_ tabViewItem: NSTabViewItem, _ window: NSWindow) {
        let container = window.frame
        let containee = tabView.subviews.first!.frame
        window.setFrame(NSRect(origin: CGPoint(x: container.origin.x, y: container.origin.y + (container.height - containee.height)),
                size: containee.size),
                display: false, animate: true)
    }
}
