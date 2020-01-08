import Foundation
import Cocoa

class Application: NSObject {
    var runningApplication: NSRunningApplication
    var axUiElement: AXUIElement?
    var axObserver: AXObserver?

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        super.init()
        if runningApplication.isFinishedLaunching {
            addAndObserveWindows()
        } else {
            runningApplication.addObserver(self, forKeyPath: "isFinishedLaunching", options: [.new], context: nil)
        }
    }

    private func addAndObserveWindows() {
        axUiElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        AXObserverCreate(runningApplication.processIdentifier, axObserverApplicationCallback, &axObserver)
        observeAllWindows()
    }

    private func observeAllWindows() {
        let windows = getActualWindows()
        debugPrint("Adding app: " + (runningApplication.bundleIdentifier ?? "nil"), windows.map { $0.title() })
        addWindows(windows)
        observeEvents(windows)
    }

    func observeNewWindows() {
        var newWindows = [AXUIElement]()
        for window in getActualWindows() {
            guard Windows.listRecentlyUsedFirst.firstIndexThatMatches(window) == nil else { continue }
            newWindows.append(window)
        }
        addWindows(newWindows)
    }

    private func getActualWindows() -> [AXUIElement] {
        return axUiElement!.windows()?.filter { $0.isActualWindow(runningApplication.isHidden) } ?? []
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let isFinishedLaunching = change![.newKey], isFinishedLaunching as! Bool else { return }
        runningApplication.removeObserver(self, forKeyPath: "isFinishedLaunching")
        addAndObserveWindows()
    }

    private func addWindows(_ windows: [AXUIElement]) {
        Windows.listRecentlyUsedFirst.insert(contentsOf: windows.map { Window($0, self) }, at: 0)
    }

    private func observeEvents(_ windows: [AXUIElement]) {
        guard let axObserver = axObserver else { return }
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        AXObserverAddNotification(axObserver, axUiElement!, kAXApplicationActivatedNotification as CFString, selfPointer)
        AXObserverAddNotification(axObserver, axUiElement!, kAXFocusedWindowChangedNotification as CFString, selfPointer)
        AXObserverAddNotification(axObserver, axUiElement!, kAXWindowCreatedNotification as CFString, selfPointer)
        AXObserverAddNotification(axObserver, axUiElement!, kAXApplicationHiddenNotification as CFString, selfPointer)
        AXObserverAddNotification(axObserver, axUiElement!, kAXApplicationShownNotification as CFString, selfPointer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
}

func axObserverApplicationCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, applicationPointer: UnsafeMutableRawPointer?) -> Void {
    let application = Unmanaged<Application>.fromOpaque(applicationPointer!).takeUnretainedValue()
    let type = notificationName as String
    debugPrint("OS event: " + type, element.title())
    switch type {
        case kAXApplicationActivatedNotification:
            guard !(App.shared as! App).appIsBeingUsed,
                  let appFocusedWindow = element.focusedWindow(),
                  let existingIndex = Windows.listRecentlyUsedFirst.firstIndexThatMatches(appFocusedWindow) else { return }
            Windows.listRecentlyUsedFirst.insert(Windows.listRecentlyUsedFirst.remove(at: existingIndex), at: 0)
        case kAXApplicationHiddenNotification, kAXApplicationShownNotification:
            for window in Windows.listRecentlyUsedFirst {
                guard window.application.axUiElement!.pid() == element.pid() else { continue }
                window.isHidden = type == kAXApplicationHiddenNotification
            }
            (App.shared as! App).refreshOpenUi()
        case kAXWindowCreatedNotification:
            guard element.isActualWindow() else { return }
            // a window being un-minimized can trigger kAXWindowCreatedNotification
            guard Windows.listRecentlyUsedFirst.firstIndexThatMatches(element) == nil else { return }
            let window = Window(element, application)
            Windows.listRecentlyUsedFirst.insert(window, at: 0)
            Windows.moveFocusedWindowIndexAfterWindowCreatedInBackground()
            // TODO: find a better way to get thumbnail of the new window
            window.refreshThumbnail()
            (App.shared as! App).refreshOpenUi()
        case kAXFocusedWindowChangedNotification:
            guard !(App.shared as! App).appIsBeingUsed,
                  element.isActualWindow(),
                  let existingIndex = Windows.listRecentlyUsedFirst.firstIndexThatMatches(element) else { return }
            Windows.listRecentlyUsedFirst.insert(Windows.listRecentlyUsedFirst.remove(at: existingIndex), at: 0)
        default: return
    }
}
