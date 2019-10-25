import Foundation
import Cocoa

struct MacroPreference<T> {
    let label: String
    let preferences: T

    init(_ label: String, _ preferences: T) {
        self.label = label
        self.preferences = preferences
    }
}

class MacroPreferenceHelper<T> {
    let macros: [MacroPreference<T>]
    var labels = [String]()
    var labelToMacro = [String: MacroPreference<T>]()

    init(_ array: [MacroPreference<T>]) {
        self.macros = array
        array.forEach {
            labelToMacro[$0.label] = $0
            labels.append($0.label)
        }
    }
}
