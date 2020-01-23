import Cocoa

class CollectionViewCenterFlowLayout: NSCollectionViewFlowLayout {
    var currentScreen: NSScreen?
    var widestRow: CGFloat?
    var totalHeight: CGFloat?

    override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes_ = super.layoutAttributesForElements(in: rect)
        guard !attributes_.isEmpty else { return attributes_ }
        let attributes = NSArray(array: attributes_, copyItems: true) as! [NSCollectionViewLayoutAttributes]
        var currentRow: [NSCollectionViewLayoutAttributes] = []
        var currentRowY = CGFloat(0)
        var currentRowWidth = CGFloat(0)
        var previousRowMaxHeight = CGFloat(0)
        var currentRowMaxHeight = CGFloat(0)
        var widestRow = CGFloat(0)
        var totalHeight = CGFloat(0)
        for (index, attribute) in attributes.enumerated() {
            let isNewRow = abs(attribute.frame.origin.y - currentRowY) > Cell.height(currentScreen!)
            if isNewRow {
                currentRowWidth -= Preferences.interCellPadding
                widestRow = max(widestRow, currentRowWidth)
                setCenteredPositionForPreviousRowCells(currentRowWidth, previousRowMaxHeight, currentRow)
                currentRow.removeAll()
                currentRowY = attribute.frame.origin.y
                currentRowWidth = 0
                previousRowMaxHeight += currentRowMaxHeight + Preferences.interCellPadding
                currentRowMaxHeight = 0
            }
            currentRow.append(attribute)
            currentRowWidth += attribute.frame.size.width + Preferences.interCellPadding
            currentRowMaxHeight = max(currentRowMaxHeight, attribute.frame.size.height)
            if index == attributes.count - 1 {
                currentRowWidth -= Preferences.interCellPadding
                widestRow = max(widestRow, currentRowWidth)
                totalHeight = previousRowMaxHeight + currentRowMaxHeight
                setCenteredPositionForPreviousRowCells(currentRowWidth, previousRowMaxHeight, currentRow)
            }
        }
        shiftCenteredElementToTheLeft(attributes, widestRow, totalHeight)
        self.widestRow = widestRow
        self.totalHeight = totalHeight
        return attributes
    }

    private func shiftCenteredElementToTheLeft(_ attributes: [NSCollectionViewLayoutAttributes], _ widestRow: CGFloat, _ totalHeight: CGFloat) {
        let horizontalMargin = ((collectionView!.frame.size.width - widestRow) / 2).rounded()
        for attribute in attributes {
            attribute.frame.origin.x -= horizontalMargin
        }
    }

    private func setCenteredPositionForPreviousRowCells(_ currentRowWidth: CGFloat, _ previousRowMaxHeight: CGFloat, _ currentRow: [NSCollectionViewLayoutAttributes]) {
        var marginLeft = (collectionView!.frame.size.width - currentRowWidth) / 2
        for attribute in currentRow {
            attribute.frame.origin.x = marginLeft
            attribute.frame.origin.y = previousRowMaxHeight
            marginLeft += attribute.frame.size.width + Preferences.interCellPadding
        }
    }
}
