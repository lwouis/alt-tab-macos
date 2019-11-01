import Cocoa

class CollectionViewCenterFlowLayout: NSCollectionViewFlowLayout {
    var currentScreen: NSScreen?

    override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes = super.layoutAttributesForElements(in: rect)
        if attributes.isEmpty {
            return attributes
        }
        var currentRow: [NSCollectionViewLayoutAttributes] = []
        var currentRowY = CGFloat(0)
        var currentRowWidth = CGFloat(0)
        var previousRowMaxY = CGFloat(0)
        var currentRowMaxY = CGFloat(0)
        var widestRow = CGFloat(0)
        var totalHeight = CGFloat(0)
        attributes.enumerated().forEach {
            let isNewRow = abs($1.frame.origin.y - currentRowY) > Screen.thumbnailMaxSize(currentScreen!).height
            if isNewRow {
                computeOriginXForAllItems(currentRowWidth - minimumInteritemSpacing, previousRowMaxY, currentRow)
                currentRow.removeAll()
                currentRowY = $1.frame.origin.y
                currentRowWidth = 0
                previousRowMaxY += currentRowMaxY + minimumLineSpacing
                currentRowMaxY = 0
            }
            currentRow.append($1)
            currentRowWidth += $1.frame.size.width + minimumInteritemSpacing
            widestRow = max(widestRow, currentRowWidth)
            currentRowMaxY = max(currentRowMaxY, $1.frame.size.height)
            if $0 == attributes.count - 1 {
                computeOriginXForAllItems(currentRowWidth - minimumInteritemSpacing, previousRowMaxY, currentRow)
                totalHeight = previousRowMaxY + currentRowMaxY
            }
        }
        collectionView!.setFrameSize(NSSize(width: widestRow - minimumInteritemSpacing, height: totalHeight))
        return attributes
    }

    func computeOriginXForAllItems(_ currentRowWidth: CGFloat, _ previousRowMaxHeight: CGFloat, _ currentRow: [NSCollectionViewLayoutAttributes]) {
        var marginLeft = floor((collectionView!.frame.size.width - currentRowWidth) / 2)
        currentRow.forEach {
            $0.frame.origin.x = marginLeft
            $0.frame.origin.y = previousRowMaxHeight
            marginLeft += $0.frame.size.width + minimumInteritemSpacing
        }
    }
}
