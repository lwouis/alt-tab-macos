import Cocoa
import Foundation

enum AXNotification: String {
    case destroyed = "AXUIElementDestroyed"
    case rezized = "AXWindowResized"
}

enum ObserverMode {
    case refreshUiOnClose
    case refreshUiOnQuit
}

class Observer: NSObject {
    var axObserver: AXObserver?
    var activeKvoObservers = [(NSRunningApplication, String?)]()

    func createObserver(_ window: TrackedWindow, _ delegate: Application, _ mode: ObserverMode) {
        let application = UnsafeMutableRawPointer(Unmanaged.passUnretained(delegate).toOpaque())

        func refreshUiOnCloseCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, delegate_: UnsafeMutableRawPointer?) -> Void {
            debugPrint("refreshUiOnCloseCallback")
            let application = Unmanaged<Application>.fromOpaque(delegate_!).takeUnretainedValue()

            if notificationName == AXNotification.rezized.rawValue as CFString {
                element.close()
                AXObserverRemoveNotification(observer, element, notificationName)
            }
            if notificationName == AXNotification.destroyed.rawValue as CFString {
                if application.appIsBeingUsed {
                    // give the system a ms to clean up
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(1), execute: {
                        application.isOutdated = true
                        application.showUiOrCycleSelection(TrackedWindows.focusedWindowIndex)
                    })
                }
                AXObserverRemoveNotification(observer, element, notificationName)
            }
        }

        if mode == .refreshUiOnClose {
            if AXObserverCreate(window.ownerPid, refreshUiOnCloseCallback, &axObserver) == .success {
                if (window.axWindow?.isFullScreen())! {
                    if AXObserverAddNotification(axObserver!, window.axWindow!, AXNotification.rezized.rawValue as CFString, application) != .success {
                        AXObserverRemoveNotification(axObserver!, window.axWindow!, AXNotification.rezized.rawValue as CFString)
                    }
                }
                if AXObserverAddNotification(axObserver!, window.axWindow!, AXNotification.destroyed.rawValue as CFString, application) != .success {
                    AXObserverRemoveNotification(axObserver!, window.axWindow!, AXNotification.destroyed.rawValue as CFString)
                }
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver!), .defaultMode)
        } else if mode == .refreshUiOnQuit {
            window.app?.addObserver(self, forKeyPath: #keyPath(NSRunningApplication.isTerminated), options: .new, context: application)
            activeKvoObservers.append((window.app!, #keyPath(NSRunningApplication.isTerminated)))
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        debugPrint("observeValue")
        if keyPath == #keyPath(NSRunningApplication.isTerminated) {
            let application = Unmanaged<Application>.fromOpaque(context!).takeUnretainedValue()
            if application.appIsBeingUsed {
                DispatchQueue.main.async(execute: {
                    application.isOutdated = true
                    application.showUiOrCycleSelection(TrackedWindows.focusedWindowIndex)
                })
            }
            (object as! NSRunningApplication).removeObserver(self, forKeyPath: keyPath!)
            activeKvoObservers = activeKvoObservers.filter { $0 != (object as! NSRunningApplication, keyPath!) }
        }
    }

    func clearObservers() {
        debugPrint("clearObservers")
        if activeKvoObservers.count > 0 {
            let activeKvoObservers_ = activeKvoObservers
            for observer in activeKvoObservers_ {
                observer.0.removeObserver(self, forKeyPath: observer.1!)
                activeKvoObservers = activeKvoObservers.filter { $0 != observer }
            }
        }
    }
}
