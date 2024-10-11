import Cocoa

class PopupButtonLikeSystemSettings: NSPopUpButton {
    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
//        showsBorderOnlyWhileMouseInside = true
//        isBordered = false
//        setButtonType(.switch)
//        let cell = cell! as! NSPopUpButtonCell
//        onAction = { _ in self.sizeToFit() }
//        cell.bezelStyle = .regularSquare
//        cell.arrowPosition = .arrowAtBottom
//        cell.imagePosition = .imageOverlaps
    }

    override var intrinsicContentSize: NSSize {
        if let selectedItem = selectedItem {
            let fakePopUpButton = NSPopUpButton()
            fakePopUpButton.addItem(withTitle: title)
            fakePopUpButton.item(at: 0)!.image = selectedItem.image
            let fakeCell = fakePopUpButton.cell! as! NSPopUpButtonCell
            let currentCell = cell! as! NSPopUpButtonCell
            fakeCell.bezelStyle = currentCell.bezelStyle
            fakeCell.arrowPosition = currentCell.arrowPosition
            fakeCell.imagePosition = currentCell.imagePosition
            fakePopUpButton.showsBorderOnlyWhileMouseInside = showsBorderOnlyWhileMouseInside
            fakePopUpButton.sizeToFit()
            return fakePopUpButton.intrinsicContentSize
        } else {
            return super.intrinsicContentSize
        }
    }
}
