import Cocoa

class Button: NSButton {
    convenience init(_ title: String, _ action: ActionClosure?) {
        self.init(title: title, target: nil, action: nil)
        onAction = action
        translatesAutoresizingMaskIntoConstraints = false
        fit()
    }
}
