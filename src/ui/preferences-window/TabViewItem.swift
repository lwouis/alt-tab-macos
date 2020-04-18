import Cocoa

class TabViewItem: NSTabViewItem {
    convenience init(_ label: String, _ imageName: NSImage.Name, _ view: NSView) {
        let viewController = NSViewController()
        self.init(viewController: viewController)
        viewController.view = view
        self.label = label
        image = NSImage(named: imageName)
    }
}
