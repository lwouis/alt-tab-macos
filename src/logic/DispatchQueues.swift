import Foundation

// OS events should be observed on background threads
class DispatchQueues {
    static let accessibilityCommands = DispatchQueue(label: "accessibilityCommands", qos: .userInteractive, attributes: .concurrent)
    static let keyboardEvents = DispatchQueue(label: "keyboardEvents", qos: .userInteractive)
}
