import Cocoa
import WebKit

class CollectionViewItem: NSCollectionViewItem {
    var view_: CollectionViewItemView { view as! CollectionViewItemView }

    override func loadView() {
        view = CollectionViewItemView()
        view.wantsLayer = true
    }

    override var isSelected: Bool {
        didSet {
            view.layer!.backgroundColor = isSelected ? Preferences.highlightBackgroundColor.cgColor : .clear
            view.layer!.borderColor = isSelected ? Preferences.highlightBorderColor.cgColor : .clear
        }
    }
}
