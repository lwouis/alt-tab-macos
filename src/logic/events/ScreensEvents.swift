import Cocoa

class ScreensEvents {
    static let debouncerScreenAndSpace = Debouncer(.main)

    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        // screen notifications often arrive in groups (e.g. 2 in a row in a short time)
        // we debounce to minimize work
        debouncerScreenAndSpace.debounce(.screenEvent) {
            Logger.debug { notification.name.rawValue }
            Spaces.refresh()
            Screens.refresh()
            // a screen added or removed, or screen resolution change can mess up layout; we reset components
            App.app.resetPreferencesDependentComponents()
        }
    }
}

final class Debouncer {
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?
    private var contextsBlocks = [DebounceContext: () -> Void]()

    init(_ queue: DispatchQueue) {
        self.queue = queue
    }

    func debounce(_ context: DebounceContext, _ block: @escaping () -> Void) {
        contextsBlocks[context] = block
        workItem?.cancel()
        let item = DispatchWorkItem(block: {
            for block in self.contextsBlocks.values {
                block()
            }
            // ScreensEvents: a screen added or removed can shuffle windows around Spaces; we refresh them
            // SpacesEvents: if UI was kept open during Space transition, the Spaces may be obsolete; we refresh them
            App.app.refreshOpenUi(Windows.list, .refreshUiAfterExternalEvent)
            Logger.info { "screens:\(NSScreen.screens.map { ($0.uuid() ?? "nil" as CFString, $0.frame) })" }
            Logger.info { "currentSpace:\(Spaces.currentSpaceIndex) (id:\(Spaces.currentSpaceId)) spaces:\(Spaces.screenSpacesMap)" }
        })
        workItem = item
        queue.asyncAfter(deadline: .now() + humanPerceptionDelay, execute: item)
    }
}

enum DebounceContext {
    case spaceEvent
    case screenEvent
}
