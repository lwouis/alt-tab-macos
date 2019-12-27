import Cocoa

class ThumbnailsPanel: NSPanel, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    var backgroundView: NSVisualEffectView?
    var collectionView_: NSCollectionView!
    var application: Application?
    let cellId = NSUserInterfaceItemIdentifier("Cell")
    var currentScreen: NSScreen?

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    }

    convenience init(_ application: Application) {
        self.init()
        self.application = application
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        hasShadow = false
        titleVisibility = .hidden
        styleMask.remove(.titled)
        backgroundColor = .clear
        collectionView_ = makeCollectionView()
        backgroundView = makeBackgroundView()
        contentView!.addSubview(backgroundView!)
        // highest level possible; this allows the app to go on top of context menus
        level = .screenSaver
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
        layout.estimatedItemSize = NSSize(width: Preferences.emptyThumbnailWidth, height: Preferences.emptyThumbnailHeight)
        layout.minimumInteritemSpacing = 5
        layout.minimumLineSpacing = 5
        return layout
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return TrackedWindows.list.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: cellId, for: indexPath) as! Cell
        item.updateWithNewContent(TrackedWindows.list[indexPath.item], application!.focusSelectedWindow, application!.thumbnailsPanel!.highlightCell, currentScreen!)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        if indexPath.item < TrackedWindows.list.count {
            let (width, height) = Cell.computeDownscaledSize(TrackedWindows.list[indexPath.item].thumbnail, currentScreen!)
            return NSSize(width: CGFloat(width) + Preferences.cellPadding * 2, height: CGFloat(height) + max(Preferences.fontHeight!, Preferences.iconSize!) + Preferences.interItemPadding + Preferences.cellPadding * 2)
        }
        return .zero
    }

    func highlightCellAt(_ step: Int) {
        collectionView_!.selectItems(at: [IndexPath(item: TrackedWindows.focusedWindowIndex, section: 0)], scrollPosition: .top)
        collectionView_!.deselectItems(at: [IndexPath(item: TrackedWindows.moveFocusedWindowIndex(-step), section: 0)])
    }

    func highlightCell(_ cell: Cell) {
        let newIndex = collectionView_.indexPath(for: cell)!
        if TrackedWindows.focusedWindowIndex != newIndex.item {
            collectionView_!.selectItems(at: [newIndex], scrollPosition: .top)
            collectionView_!.deselectItems(at: [IndexPath(item: TrackedWindows.focusedWindowIndex, section: 0)])
            TrackedWindows.focusedWindowIndex = newIndex.item
        }
    }

    func computeThumbnails(_ currentScreen: NSScreen) {
        self.currentScreen = currentScreen
        (collectionView_.collectionViewLayout as! CollectionViewCenterFlowLayout).currentScreen = currentScreen
        collectionView_!.setFrameSize(Screen.thumbnailPanelMaxSize(currentScreen))
        collectionView_!.collectionViewLayout!.invalidateLayout()
        collectionView_!.reloadData()
        collectionView_!.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: collectionView_!.frame.size.width + Preferences.windowPadding * 2, height: collectionView_!.frame.size.height + Preferences.windowPadding * 2))
        backgroundView!.setFrameSize(frame.size)
        collectionView_!.setFrameOrigin(NSPoint(x: Preferences.windowPadding, y: Preferences.windowPadding))
    }
}
