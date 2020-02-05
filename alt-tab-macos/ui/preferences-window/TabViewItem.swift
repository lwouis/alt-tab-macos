import Cocoa
import Foundation

class TabViewItem {
    static func make(_ label: String, _ imageNAme: NSImage.Name, _ view: NSView) -> NSTabViewItem {
        let viewController = NSViewController()
        let tabViewItem = NSTabViewItem(viewController: viewController)
        viewController.view = view
        tabViewItem.label = label
        tabViewItem.image = NSImage(named: imageNAme)
        return tabViewItem
    }
}
