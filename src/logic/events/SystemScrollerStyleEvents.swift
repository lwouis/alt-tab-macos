import Cocoa

class SystemScrollerStyleEvents {
    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        logger.d(notification.name.rawValue)
        logger.i(App.app.thumbnailsPanel.thumbnailsView.scrollView.scrollerStyle == .overlay ? "overlay" : "legacy")
        // force overlay style after a change in System Preference > General > Show scroll bars
        App.app.thumbnailsPanel?.thumbnailsView.scrollView.scrollerStyle = .overlay
    }
}
