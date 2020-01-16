import Cocoa

class CollectionViewCenterFlowLayout: NSCollectionViewFlowLayout {
    var currentScreen: NSScreen?

    override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes_ = super.layoutAttributesForElements(in: rect)
        guard !attributes_.isEmpty else { return attributes_ }
        let attributes = NSArray(array: attributes_, copyItems: true) as! [NSCollectionViewLayoutAttributes]
        var currentRow: [NSCollectionViewLayoutAttributes] = []
        var currentRowY = CGFloat(0)
        var currentRowWidth = CGFloat(0)
        var previousRowMaxY = CGFloat(0)
        var currentRowMaxY = CGFloat(0)
        var widestRow = CGFloat(0)
        var totalHeight = CGFloat(0)
        for (index, attribute) in attributes.enumerated() {
            let isNewRow = abs(attribute.frame.origin.y - currentRowY) > Cell.height(currentScreen!)
            if isNewRow {
                computeOriginXForAllItems(currentRowWidth - Preferences.cellPadding, previousRowMaxY, currentRow)
                currentRow.removeAll()
                currentRowY = attribute.frame.origin.y
                currentRowWidth = 0
                previousRowMaxY += currentRowMaxY + Preferences.cellPadding
                currentRowMaxY = 0
            }
            currentRow.append(attribute)
            currentRowWidth += attribute.frame.size.width + Preferences.cellPadding
            widestRow = max(widestRow, currentRowWidth)
            currentRowMaxY = max(currentRowMaxY, attribute.frame.size.height)
            if index == attributes.count - 1 {
                computeOriginXForAllItems(currentRowWidth - Preferences.cellPadding, previousRowMaxY, currentRow)
                totalHeight = previousRowMaxY + currentRowMaxY
            }
        }
        let newWidth = widestRow - Preferences.cellPadding
        collectionView!.bounds.origin.x = (collectionView!.frame.size.width - newWidth) / 2
        collectionView!.frame.size.width = newWidth
        collectionView!.frame.size.height = totalHeight
        return attributes
    }

    private func computeOriginXForAllItems(_ currentRowWidth: CGFloat, _ previousRowMaxHeight: CGFloat, _ currentRow: [NSCollectionViewLayoutAttributes]) {
        var marginLeft = (collectionView!.frame.size.width - currentRowWidth) / 2
        for attribute in currentRow {
            attribute.frame.origin.x = marginLeft
            attribute.frame.origin.y = previousRowMaxHeight
            marginLeft += attribute.frame.size.width + Preferences.cellPadding
        }
    }
}
