import Foundation

// OS events should be observed on background threads
class DispatchQueues {
    static let focusActions = DispatchQueue(label: "focusActions", qos: .userInteractive)
    static let keyboardEvents = DispatchQueue(label: "keyboardEvents", qos: .userInteractive)
}
