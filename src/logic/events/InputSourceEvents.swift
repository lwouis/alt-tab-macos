import Cocoa
import Carbon.HIToolbox.TextInputSources

class InputSourceEvents: NSObject {
    private static let observer = InputSourceEvents()
    private static var isObserving = false

    static func observe() {
        guard !isObserving else { return }
        isObserving = true
        let name = NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String)
        DistributedNotificationCenter.default().addObserver(observer, selector: #selector(handleEvent), name: name, object: nil, suspensionBehavior: .deliverImmediately)
    }

    @objc private func handleEvent(_ notification: Notification) {
        Logger.debug { InputSourceEvents.currentInputSource() }
        ControlsTab.inputSourceChanged()
    }

    static func currentInputSource() -> String {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let localizedNamePointer = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) else { return "unknown" }
        let localizedName = Unmanaged<AnyObject>.fromOpaque(localizedNamePointer).takeUnretainedValue()
        return localizedName as? String ?? "unknown"
    }
}
