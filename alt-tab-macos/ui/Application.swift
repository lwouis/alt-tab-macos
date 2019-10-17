import Foundation
import Cocoa

let cellId = NSUserInterfaceItemIdentifier("Cell")

func updateThumbnailMaxSize() -> Void {
    let main = NSScreen.main!.frame
    Preferences.thumbnailMaxWidth = (NSScreen.main!.frame.size.width * Preferences.maxScreenUsage - Preferences.windowPadding * 2) / Preferences.maxThumbnailsPerRow - Preferences.interItemPadding
    Preferences.thumbnailMaxHeight = Preferences.thumbnailMaxWidth * (main.height / main.width)
}

class Application: NSApplication, NSApplicationDelegate, NSWindowDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSCollectionViewDelegateFlowLayout {
    var item: NSStatusItem?
    var backgroundView: NSVisualEffectView?
    var collectionView_: NSCollectionView?
    var window: NSPanel?
    var selectedOpenWindow: Int = 0
    var numberOfColumns: Int = 0
    var openWindows: [OpenWindow] = []
    var workItems: [DispatchWorkItem] = []
    var isFirstSummon: Bool = true
    var appIsBeingUsed: Bool = false

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ensureScreenRecordingCheckboxIsChecked()
        ensureAccessibilityCheckboxIsChecked()
        updateThumbnailMaxSize()
        makeStatusBarItem()
        makeWindow()
        makeCollectionView()
        backgroundView = NSVisualEffectView()
        backgroundView!.blendingMode = .behindWindow
        backgroundView!.material = .dark
        backgroundView!.state = .active
        backgroundView!.addSubview(collectionView_!)
        window!.contentView = backgroundView
        listenToGlobalKeyboardEvents(self)
        listenToScreenChanges()
        Application.shared.activate(ignoringOtherApps: true)
        Application.shared.runModal(for: window!)
        Application.shared.hide(nil)
    }

    func listenToScreenChanges() {
        NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: NSApplication.shared,
                queue: OperationQueue.main
        ) { notification -> Void in
            updateThumbnailMaxSize()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !appIsBeingUsed {
            focusSelectedWindow(currentlySelectedWindow())
        }
    }

    func makeCollectionView() {
        let layout = CollectionViewCenterFlowLayout()
        layout.estimatedItemSize = NSSize(width: Preferences.thumbnailMaxWidth, height: Preferences.thumbnailMaxHeight)
        layout.minimumInteritemSpacing = 5
        layout.minimumLineSpacing = 5
        collectionView_ = NSCollectionView()
        collectionView_!.dataSource = self
        collectionView_!.delegate = self
        collectionView_!.collectionViewLayout = layout
        collectionView_!.backgroundColors = [.clear]
        collectionView_!.isSelectable = true
        collectionView_!.allowsMultipleSelection = false
        collectionView_!.register(Cell.self, forItemWithIdentifier: cellId)
    }

    func makeWindow() {
        window = NSPanel()
        window!.styleMask = [.borderless]
        window!.level = .floating
        window!.animationBehavior = NSWindow.AnimationBehavior.none
        window!.backgroundColor = .clear
        window!.setIsVisible(true)
        window!.delegate = self
    }

    func makeStatusBarItem() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item!.button!.title = "AltTab"
        item!.menu = NSMenu()
        item!.menu!.addItem(
                withTitle: "Version #VERSION#",
                action: nil,
                keyEquivalent: "")
        item!.menu!.addItem(
                withTitle: "Quit \(ProcessInfo.processInfo.processName)",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q")
    }

    func ensureAccessibilityCheckboxIsChecked() {
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Accessibility.\nPlease authorize and re-launch.\nSee https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx")
            NSApp.terminate(self)
        }
    }

    func ensureScreenRecordingCheckboxIsChecked() {
        let firstWindow = cgWindows()[0]
        let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, firstWindow[kCGWindowNumber] as! CGWindowID, [.boundsIgnoreFraming, .bestResolution])
        if windowImage == nil {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Screen Recording.\nPlease authorize and re-launch.\nSee https://dropshare.zendesk.com/hc/en-us/articles/360033453434-Enabling-Screen-Recording-Permission-on-macOS-Catalina-10-15-")
            NSApp.terminate(self)
        }
    }

    func computeOpenWindows() {
        openWindows.removeAll()
        // we rely on the fact that CG and AX APIs arrays follow the same order to match objects from both APIs
        var pidAndCurrentIndex: [pid_t: Int] = [:]
        for cgWindow in cgWindows() {
            let cgId = cgWindow[kCGWindowNumber] as! CGWindowID
            let cgTitle = cgWindow[kCGWindowName] as? String ?? ""
            let cgOwnerName = cgWindow[kCGWindowOwnerName] as? String ?? ""
            let cellTitle = cgTitle.isEmpty ? cgOwnerName : cgTitle
            let cgOwnerPid = cgWindow[kCGWindowOwnerPID] as! pid_t
            let i = pidAndCurrentIndex.index(forKey: cgOwnerPid)
            pidAndCurrentIndex[cgOwnerPid] = (i == nil ? 0 : pidAndCurrentIndex[i!].value + 1)
            let axWindows_ = axWindows(cgOwnerPid)
            // windows may have changed between the CG and the AX calls
            if axWindows_.count > pidAndCurrentIndex[cgOwnerPid]! {
                openWindows.append(OpenWindow(target: axWindows_[pidAndCurrentIndex[cgOwnerPid]!], ownerPid: cgOwnerPid, cgId: cgId, cgTitle: cellTitle))
            }
        }
    }

    func highlightThumbnail(_ step: Int) {
        collectionView_!.selectItems(at: [IndexPath(item: selectedOpenWindow, section: 0)], scrollPosition: .top)
        collectionView_!.deselectItems(at: [IndexPath(item: cellWithStep(-step), section: 0)])
    }

    func computeThumbnails() {
        let maxSize = NSSize(width: NSScreen.main!.frame.width * Preferences.maxScreenUsage, height: NSScreen.main!.frame.height * Preferences.maxScreenUsage)
        collectionView_!.setFrameSize(maxSize)
        collectionView_!.collectionViewLayout!.invalidateLayout()
        collectionView_!.reloadData()
        collectionView_!.layoutSubtreeIfNeeded()
        window!.setContentSize(NSSize(width: collectionView_!.frame.size.width + Preferences.windowPadding * 2, height: collectionView_!.frame.size.height + Preferences.windowPadding * 2))
        backgroundView!.setFrameSize(window!.frame.size)
        collectionView_!.setFrameOrigin(NSPoint(x: Preferences.windowPadding, y: Preferences.windowPadding))
        window!.center()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
//        debugPrint("collectionView: count items", openWindows.count)
        return openWindows.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
//        debugPrint("collectionView: make item", indexPath.item)
        let item = collectionView.makeItem(withIdentifier: cellId, for: indexPath) as! Cell
        item.updateWithNewContent(openWindows[indexPath.item], self.focusSelectedWindow)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
//        debugPrint("collectionView: item size")
        if indexPath.item < openWindows.count {
            let (width, height) = computeDownscaledSize(openWindows[indexPath.item].thumbnail)
            return NSSize(width: CGFloat(width) + Preferences.cellPadding * 2, height: CGFloat(height) + max(Preferences.fontHeight, Preferences.iconSize) + Preferences.interItemPadding + Preferences.cellPadding * 2)
        }
        return .zero
    }

    func cellWithStep(_ step: Int) -> Int {
        selectedOpenWindow + step < 0 ? openWindows.count - 1 : (selectedOpenWindow + step) % openWindows.count
    }

    func selectOtherCell(_ step: Int) {
        appIsBeingUsed = true
        if openWindows.count > 0 {
            selectedOpenWindow = cellWithStep(step)
            if isFirstSummon {
                isFirstSummon = false
                let workItem = DispatchWorkItem {
                    self.computeOpenWindows()
                    self.computeThumbnails()
                    self.highlightThumbnail(step)
                    Application.shared.unhideWithoutActivation()
                }
                workItems.append(workItem)
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay, execute: workItem)
            } else {
                highlightThumbnail(step)
            }
        }
    }

    func currentlySelectedWindow() -> OpenWindow? {
        openWindows.count > selectedOpenWindow ? openWindows[selectedOpenWindow] : nil
    }

    func focusSelectedWindow(_ window: OpenWindow?) {
        workItems.forEach({ $0.cancel() })
        workItems.removeAll()
        window?.focus()
        Application.shared.hide(nil)
        appIsBeingUsed = false
        isFirstSummon = true
    }

    func keyDownMeta() {
        debugPrint("meta down")
        computeOpenWindows()
        selectedOpenWindow = 0
    }

    func keyDownMetaTab() {
        debugPrint("meta+tab down")
        selectOtherCell(1)
    }

    func keyDownMetaShiftTab() {
        debugPrint("meta+shift+tab down")
        selectOtherCell(-1)
    }

    func keyUpMeta() {
        debugPrint("meta up")
        if appIsBeingUsed {
            focusSelectedWindow(currentlySelectedWindow())
        }
    }
}
