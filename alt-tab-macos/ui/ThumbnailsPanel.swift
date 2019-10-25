import Cocoa

class ThumbnailsPanel: NSPanel, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    var backgroundView: NSVisualEffectView?
    var collectionView_: NSCollectionView!
    var application: Application?
    let cellId = NSUserInterfaceItemIdentifier("Cell")

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    convenience init(_ application: Application) {
        self.init()
        self.application = application
        isFloatingPanel = true
        animationBehavior = NSWindow.AnimationBehavior.none
        hidesOnDeactivate = false
        hasShadow = false
        titleVisibility = .hidden
        styleMask.remove(.titled)
        backgroundColor = .clear
        collectionView_ = makeCollectionView()
        backgroundView = makeBackgroundView()
        contentView!.addSubview(backgroundView!)
    }

    private func makeBackgroundView() -> NSVisualEffectView {
        let backgroundView = NSVisualEffectView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.material = Preferences.windowMaterial
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer!.cornerRadius = Preferences.windowCornerRadius!
        backgroundView.addSubview(collectionView_)
        return backgroundView
    }

    func makeCollectionView() -> NSCollectionView {
        let collectionView_ = NSCollectionView()
        collectionView_.dataSource = self
        collectionView_.delegate = self
        collectionView_.collectionViewLayout = makeLayout()
        collectionView_.backgroundColors = [.clear]
        collectionView_.isSelectable = true
        collectionView_.allowsMultipleSelection = false
        collectionView_.register(Cell.self, forItemWithIdentifier: cellId)
        return collectionView_
    }

    func makeLayout() -> CollectionViewCenterFlowLayout {
        let layout = CollectionViewCenterFlowLayout()
        layout.estimatedItemSize = NSSize(width: Preferences.thumbnailMaxWidth, height: Preferences.thumbnailMaxHeight)
        layout.minimumInteritemSpacing = 5
        layout.minimumLineSpacing = 5
        return layout
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
//        debugPrint("collectionView: count items", openWindows.count)
        application!.openWindows.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
//        debugPrint("collectionView: make item", indexPath.item)
        let item = collectionView.makeItem(withIdentifier: cellId, for: indexPath) as! Cell
        item.updateWithNewContent(application!.openWindows[indexPath.item], application!.focusSelectedWindow)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
//        debugPrint("collectionView: item size")
        if indexPath.item < application!.openWindows.count {
            let (width, height) = computeDownscaledSize(application!.openWindows[indexPath.item].thumbnail)
            return NSSize(width: CGFloat(width) + Preferences.cellPadding * 2, height: CGFloat(height) + max(Preferences.fontHeight!, Preferences.iconSize!) + Preferences.interItemPadding + Preferences.cellPadding * 2)
        }
        return .zero
    }

    func highlightCell(_ step: Int) {
        collectionView_!.selectItems(at: [IndexPath(item: application!.selectedOpenWindow, section: 0)], scrollPosition: .top)
        collectionView_!.deselectItems(at: [IndexPath(item: application!.cellWithStep(-step), section: 0)])
    }

    func computeThumbnails() {
        let maxSize = NSSize(width: NSScreen.main!.frame.width * Preferences.maxScreenUsage!, height: NSScreen.main!.frame.height * Preferences.maxScreenUsage!)
        collectionView_!.setFrameSize(maxSize)
        collectionView_!.collectionViewLayout!.invalidateLayout()
        collectionView_!.reloadData()
        collectionView_!.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: collectionView_!.frame.size.width + Preferences.windowPadding * 2, height: collectionView_!.frame.size.height + Preferences.windowPadding * 2))
        backgroundView!.setFrameSize(frame.size)
        collectionView_!.setFrameOrigin(NSPoint(x: Preferences.windowPadding, y: Preferences.windowPadding))
    }
}
