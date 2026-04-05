import Cocoa

class ContextMenuEvents {
    private static var isEnabled = false
    private static var beginObserver: NSObjectProtocol?
    private static var endObserver: NSObjectProtocol?
    private static var openMenuCount = 0

    static var isMenuOpen: Bool { openMenuCount > 0 }

    static func toggle(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startObserving()
        } else {
            stopObserving()
        }
    }

    private static func startObserving() {
        guard beginObserver == nil, endObserver == nil else { return }
        let center = NotificationCenter.default
        beginObserver = center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            openMenuCount += 1
        }
        endObserver = center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            openMenuCount = max(0, openMenuCount - 1)
        }
    }

    private static func stopObserving() {
        openMenuCount = 0
        let center = NotificationCenter.default
        if let beginObserver {
            center.removeObserver(beginObserver)
            self.beginObserver = nil
        }
        if let endObserver {
            center.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
