import Cocoa

class SystemScrollerStyleEvents {
    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        Logger.debug { notification.name.rawValue }
        Logger.info { TilesView.scrollView.scrollerStyle == .overlay ? "overlay" : "legacy" }
        // force overlay style after a change in System Preference > General > Show scroll bars
        TilesView.scrollView.scrollerStyle = .overlay
    }
}
