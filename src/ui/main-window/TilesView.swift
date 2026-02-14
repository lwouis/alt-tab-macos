import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

enum SearchMode {
    case off
    case editing
    case locked
}

class TilesView: NSObject {
    var scrollView: ScrollView!
    var contentView: EffectView!
    var searchField = NSSearchField(frame: .zero)
    private(set) var searchMode: SearchMode = .off
    var rows = [[TileView]]()
    private var lastRowSignature = [Int]()
    static var recycledViews = [TileView]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)
    static var layoutCache = LayoutCache()
    var thumbnailUnderLayer = TileUnderLayer()
    var thumbnailOverView = TileOverView()

    override init() {
        super.init()
        configureSearchField()
        updateBackgroundView()
        // TODO: think about this optimization more
        (1...20).forEach { _ in TilesView.recycledViews.append(TileView()) }
        Self.updateCachedSizes()
    }

    var isSearchModeOn: Bool { searchMode != .off }
    var isSearchEditing: Bool { searchMode == .editing }
    var isSearchLocked: Bool { searchMode == .locked }

    func startSearchSession(_ startInSearchMode: Bool) {
        searchField.stringValue = ""
        Windows.updateSearchQuery("")
        searchMode = startInSearchMode ? .editing : .off
        updateSearchFieldEditability()
    }

    func endSearchSession() {
        searchField.stringValue = ""
        Windows.updateSearchQuery("")
        searchMode = .off
        updateSearchFieldEditability()
    }

    func toggleSearchModeFromShortcut() {
        if searchMode == .off {
            enableSearchEditing()
        } else if searchMode == .editing {
            disableSearchMode()
        } else {
            enableSearchEditing()
        }
    }

    func disableSearchMode() {
        guard searchMode != .off else { return }
        searchMode = .off
        updateSearchFieldEditability()
        searchField.stringValue = ""
        clearHover()
        Windows.updateSearchQuery("")
        App.app.refreshUi(true)
        focusSelectedTileIfPossible()
    }

    func lockSearchMode() {
        if searchMode == .editing {
            searchMode = .locked
            updateSearchFieldEditability()
            focusSelectedTileIfPossible()
        } else if searchMode == .locked {
            enableSearchEditing()
        }
    }

    func enableSearchEditing() {
        guard searchMode != .editing else {
            placeSearchCaretAtEnd()
            return
        }
        let wasOff = searchMode == .off
        searchMode = .editing
        updateSearchFieldEditability()
        App.app.forceDoNothingOnRelease = true
        clearHover()
        stopKeyRepeatTimers()
        if wasOff {
            App.app.refreshUi(true)
        }
        App.app.thumbnailsPanel.makeFirstResponder(searchField)
        placeSearchCaretAtEnd()
    }

    func handleSearchEditingKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        if keyCode == UInt16(kVK_LeftArrow) { App.app.cycleSelection(.left); return true }
        if keyCode == UInt16(kVK_RightArrow) { App.app.cycleSelection(.right); return true }
        if keyCode == UInt16(kVK_UpArrow) { App.app.cycleSelection(.up); return true }
        if keyCode == UInt16(kVK_DownArrow) { App.app.cycleSelection(.down); return true }
        if keyCode == UInt16(kVK_Space) { return false }
        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) {
            deleteSearchCharacter(keyCode)
            return true
        }
        if let insertedText = insertedSearchText(from: event) {
            appendSearchText(insertedText)
            return true
        }
        if matchesShortcut(event, "cancelShortcut") {
            App.app.cancelSearchModeOrHideUi()
            return true
        }
        if matchesSearchShortcut(event) {
            toggleSearchModeFromShortcut()
            return true
        }
        return false
    }

    private func configureSearchField() {
        searchField.placeholderString = NSLocalizedString("Search", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) {
            searchField.controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            searchField.controlSize = .large
        } else {
            searchField.controlSize = .regular
        }
        searchField.usesSingleLineMode = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        updateSearchFieldEditability()
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        updateSearchQuery(sender.stringValue)
    }

    private func updateSearchQuery(_ query: String) {
        if Windows.searchQuery == query { return }
        clearHover()
        Windows.updateSearchQuery(query)
        stopKeyRepeatTimers()
        App.app.refreshUi(true)
    }

    private func appendSearchText(_ text: String) {
        guard !text.isEmpty else { return }
        if let editor = searchField.currentEditor() {
            let current = searchField.stringValue as NSString
            let range = clampedSelectionRange(current.length, editor.selectedRange)
            searchField.stringValue = current.replacingCharacters(in: range, with: text)
            editor.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
        } else {
            searchField.stringValue += text
        }
        updateSearchQuery(searchField.stringValue)
    }

    private func deleteSearchCharacter(_ keyCode: UInt16) {
        guard !searchField.stringValue.isEmpty else { return }
        if let editor = searchField.currentEditor() {
            let current = searchField.stringValue as NSString
            var range = clampedSelectionRange(current.length, editor.selectedRange)
            if range.length == 0 {
                if keyCode == UInt16(kVK_Delete) {
                    guard range.location > 0 else { return }
                    range = NSRange(location: range.location - 1, length: 1)
                } else {
                    guard range.location < current.length else { return }
                    range = NSRange(location: range.location, length: 1)
                }
            }
            searchField.stringValue = current.replacingCharacters(in: range, with: "")
            editor.selectedRange = NSRange(location: range.location, length: 0)
        } else {
            searchField.stringValue.removeLast()
        }
        updateSearchQuery(searchField.stringValue)
    }

    private func clampedSelectionRange(_ stringLength: Int, _ selectedRange: NSRange) -> NSRange {
        let location = max(0, min(selectedRange.location, stringLength))
        let length = max(0, min(selectedRange.length, stringLength - location))
        return NSRange(location: location, length: length)
    }

    private func clearHover() {
        if let oldHoveredWindowIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            TilesView.highlight(oldHoveredWindowIndex)
            TilesView.highlight(Windows.selectedWindowIndex)
        }
    }

    private func stopKeyRepeatTimers() {
        KeyRepeatTimer.stopTimerForRepeatingKey(Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex))
        KeyRepeatTimer.stopTimerForRepeatingKey("previousWindowShortcut")
    }

    private func focusSelectedTileIfPossible() {
        guard Windows.selectedWindowIndex >= 0, Windows.selectedWindowIndex < TilesView.recycledViews.count else { return }
        App.app.thumbnailsPanel.makeFirstResponder(TilesView.recycledViews[Windows.selectedWindowIndex])
    }

    private func placeSearchCaretAtEnd() {
        guard searchMode == .editing else { return }
        if App.app.thumbnailsPanel.firstResponder !== searchField.currentEditor() {
            App.app.thumbnailsPanel.makeFirstResponder(searchField)
        }
        guard let editor = searchField.currentEditor() else { return }
        let end = searchField.stringValue.utf16.count
        editor.selectedRange = NSRange(location: end, length: 0)
    }

    private func insertedSearchText(from event: NSEvent) -> String? {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.function) {
            return nil
        }
        let keyCode = event.keyCode
        if keyCode == UInt16(kVK_Tab) || keyCode == UInt16(kVK_Escape) || keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            return nil
        }
        if keyCode == UInt16(kVK_LeftArrow) || keyCode == UInt16(kVK_RightArrow) || keyCode == UInt16(kVK_UpArrow) || keyCode == UInt16(kVK_DownArrow) || keyCode == UInt16(kVK_Home) || keyCode == UInt16(kVK_End) || keyCode == UInt16(kVK_PageUp) || keyCode == UInt16(kVK_PageDown) {
            return nil
        }
        guard let value = event.charactersIgnoringModifiers, value.count == 1 else { return nil }
        guard let scalar = value.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return String(value)
    }

    private func matchesSearchShortcut(_ event: NSEvent) -> Bool {
        matchesShortcut(event, "searchShortcut")
    }

    private func updateSearchFieldEditability() {
        let editable = searchMode == .editing
        searchField.isEditable = editable
        searchField.isSelectable = editable
    }

    private func matchesShortcut(_ event: NSEvent, _ shortcutId: String) -> Bool {
        guard let shortcut = ControlsTab.shortcuts[shortcutId]?.shortcut else { return false }
        if shortcut.keyCode == .none || shortcut.carbonKeyCode != UInt32(event.keyCode) { return false }
        let holdModifiers = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.app.shortcutIndex)]?.shortcut.carbonModifierFlags.cleaned() ?? 0
        let eventModifiers = cocoaToCarbonFlags(event.modifierFlags).cleaned()
        let shortcutModifiers = shortcut.carbonModifierFlags.cleaned()
        return eventModifiers == shortcutModifiers || eventModifiers == (shortcutModifiers | holdModifiers)
    }

    static func updateCachedSizes() {
        guard let firstView = TilesView.recycledViews.first else { return }
        layoutCache.labelHeight = firstView.label.cell!.cellSize.height
        let iconCellSize = firstView.statusIcons.iconCellSize
        layoutCache.iconWidth = iconCellSize.width
        layoutCache.iconHeight = iconCellSize.height
        layoutCache.comfortableReadabilityWidth = TileView.widthOfComfortableReadability()
        TileFontIconView.warmCaches(symbols: [.circledPlusSign, .circledMinusSign, .circledSlashSign, .circledNumber0, .circledNumber10, .circledStar], size: Appearance.fontHeight, color: Appearance.fontColor)
    }

    func updateBackgroundView() {
        contentView = makeAppropriateEffectView()
        scrollView = ScrollView()
        searchField.isHidden = searchMode == .off
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
    }

    func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        NSScreen.updatePreferred()
        Appearance.update()
        // thumbnails are captured continuously. They will pick up the new size on the next cycle
        TilesPanel.updateMaxPossibleThumbnailSize()
        // app icons are captured once at launch; we need to manually update them if needed
        let old = TilesPanel.maxPossibleAppIconSize.width
        TilesPanel.updateMaxPossibleAppIconSize()
        if old != TilesPanel.maxPossibleAppIconSize.width {
            Applications.updateAppIcons()
        }
        updateBackgroundView()
        App.app.thumbnailsPanel.contentView = contentView
        for i in 0..<TilesView.recycledViews.count {
            TilesView.recycledViews[i] = TileView()
        }
        thumbnailUnderLayer = TileUnderLayer()
        thumbnailOverView = TileOverView()
        thumbnailOverView.scrollView = scrollView
        lastRowSignature.removeAll()
        Self.updateCachedSizes()
    }

    static func highlight(_ indexInRecycledViews: Int) {
        guard indexInRecycledViews >= 0, indexInRecycledViews < recycledViews.count else { return }
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        guard view.frame != .zero else { return }
        view.drawHighlight()
        let underLayer = App.app.thumbnailsPanel.tilesView.thumbnailUnderLayer
        guard Windows.selectedWindowIndex >= 0, Windows.selectedWindowIndex < recycledViews.count else { return }
        let focusedView = recycledViews[Windows.selectedWindowIndex]
        let hoveredView = Windows.hoveredWindowIndex.flatMap { $0 >= 0 && $0 < recycledViews.count ? recycledViews[$0] : nil }
        underLayer.updateHighlight(
            focusedView: focusedView.frame != .zero ? focusedView : nil,
            hoveredView: hoveredView != focusedView && hoveredView?.frame != .zero ? hoveredView : nil
        )
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [TileView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.selectedWindow()?.rowIndex {
            var nextRow = currentRow + step
            if nextRow >= rows.count {
                if allowWrap {
                    nextRow = nextRow % rows.count
                } else {
                    return nil
                }
            } else if nextRow < 0 {
                if allowWrap {
                    nextRow = rows.count + nextRow
                } else {
                    return nil
                }
            }
            if ((step > 0 && nextRow < currentRow) || (step < 0 && nextRow > currentRow)) &&
                   (ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended) {
                return nil
            }
            return rows[nextRow]
        }
        return nil
    }

    func navigateUpOrDown(_ direction: Direction, allowWrap: Bool = true) {
        guard Windows.selectedWindowIndex < TilesView.recycledViews.count else { return }
        let focusedViewFrame = TilesView.recycledViews[Windows.selectedWindowIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        guard let targetRow = nextRow(direction, allowWrap: allowWrap), !targetRow.isEmpty else { return }
        let leftSide = originCenter < NSMidX(contentView.frame)
        let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
        let iterable = leadingSide ? targetRow : targetRow.reversed()
        guard let targetView = iterable.first(where: {
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
            }
            return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
        }) ?? iterable.last else { return }
        guard let targetIndex = TilesView.recycledViews.firstIndex(of: targetView) else { return }
        Windows.updateSelectedAndHoveredWindowIndex(targetIndex)
    }

    func updateItemsAndLayout(_ preservedScrollOrigin: CGPoint?) {
        let widthMax = TilesPanel.maxThumbnailsWidth().rounded()
        if let (maxX, maxY, labelHeight, rowSignature) = layoutTileViews(widthMax) {
            layoutParentViews(maxX, widthMax, maxY, labelHeight)
            if Preferences.alignThumbnails == .center {
                centerRows(TilesView.thumbnailsWidth)
            }
            if rowSignature != lastRowSignature {
                for row in rows {
                    for (j, view) in row.enumerated() {
                        view.numberOfViewsInRow = row.count
                        view.isFirstInRow = j == 0
                        view.isLastInRow = j == row.count - 1
                        view.indexInRow = j
                    }
                }
                lastRowSignature = rowSignature
            }
            highlightStartView()
            if let preservedScrollOrigin {
                restoreScrollOrigin(preservedScrollOrigin)
            }
        }
    }

    func currentScrollOrigin() -> CGPoint {
        scrollView.contentView.bounds.origin
    }

    private func restoreScrollOrigin(_ scrollOrigin: CGPoint) {
        guard let documentView = scrollView.documentView else { return }
        let visibleSize = scrollView.contentView.bounds.size
        let documentSize = documentView.frame.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let clampedOrigin = CGPoint(x: min(max(0, scrollOrigin.x), maxX), y: min(max(0, scrollOrigin.y), maxY))
        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func layoutTileViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat, [Int])? {
        let labelHeight = Self.layoutCache.labelHeight
        let height = TileView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [TileView]()
        var rowSignature = [Int]()
        rows.removeAll(keepingCapacity: true)
        rows.append([TileView]())
        var index = 0
        while index < TilesView.recycledViews.count {
            guard App.app.appIsBeingUsed else { return nil }
            defer { index = index + 1 }
            let view = TilesView.recycledViews[index]
            if index < Windows.list.count {
                let window = Windows.list[index]
                guard Windows.shouldDisplay(window) else {
                    view.frame = .zero
                    continue
                }
                view.updateRecycledCellWithNewContent(window, index, height)
                let width = view.frame.size.width
                let projectedX = projectedWidth(currentX, width).rounded(.down)
                if needNewLine(projectedX, widthMax) {
                    currentX = startingX
                    currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedWidth(currentX, width).rounded(.down)
                    maxY = max(currentY + height + Appearance.interCellPadding, maxY)
                    rows.append([TileView]())
                } else {
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedX
                    maxX = max(isLeftToRight ? currentX : widthMax - currentX, maxX)
                }
                rows[rows.count - 1].append(view)
                newViews.append(view)
                rowSignature.append(index)
                window.rowIndex = rows.count - 1
            } else {
                // release images from unused recycledViews; they take lots of RAM
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
            }
        }
        scrollView.documentView!.subviews = newViews
        scrollView.documentView!.addSubview(thumbnailOverView)
        thumbnailOverView.scrollView = scrollView
        let docLayer = scrollView.documentView!.layer!
        if thumbnailUnderLayer.superlayer !== docLayer {
            docLayer.insertSublayer(thumbnailUnderLayer, at: 0)
        }
        return (maxX, maxY, labelHeight, rowSignature)
    }

    private func needNewLine(_ projectedX: CGFloat, _ widthMax: CGFloat) -> Bool {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return projectedX > widthMax
        }
        return projectedX < 0
    }

    private func projectedWidth(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return currentX + width + Appearance.interCellPadding
        }
        return currentX - width - Appearance.interCellPadding
    }

    private func localizedCurrentX(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX : currentX - width
    }

    private func layoutParentViews(_ maxX: CGFloat, _ widthMax: CGFloat, _ maxY: CGFloat, _ labelHeight: CGFloat) {
        let searchBarHeight = searchBarHeight()
        let searchBottomPadding = CGFloat(10)
        let searchReservedHeight = searchMode == .off ? 0 : searchBarHeight + searchBottomPadding
        let heightMax = max(0, TilesPanel.maxThumbnailsHeight() - searchReservedHeight)
        let minSearchWidth = min(widthMax, 320)
        TilesView.thumbnailsWidth = max(min(maxX, widthMax), searchMode == .off ? 0 : minSearchWidth)
        TilesView.thumbnailsHeight = min(maxY, heightMax)
        let appIconsBottomViewportPadding = appIconsBottomViewportPadding(maxY, heightMax, labelHeight)
        let frameWidth = TilesView.thumbnailsWidth + Appearance.windowPadding * 2
        var frameHeight = TilesView.thumbnailsHeight + Appearance.windowPadding * 2 + searchReservedHeight
        let originX = Appearance.windowPadding
        var originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        let scrollHeight = max(0, min(maxY, heightMax) - appIconsBottomViewportPadding * 2)
        scrollView.frame.size = NSSize(width: TilesView.thumbnailsWidth, height: scrollHeight)
        scrollView.frame.origin = CGPoint(x: originX, y: originY + appIconsBottomViewportPadding * 2)
        scrollView.contentView.frame.size = scrollView.frame.size
        searchField.isHidden = searchMode == .off
        if searchMode != .off {
            searchField.frame.size = NSSize(width: TilesView.thumbnailsWidth, height: searchBarHeight)
            searchField.frame.origin = CGPoint(x: originX, y: frameHeight - Appearance.windowPadding - searchBarHeight)
        }
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = max(0, TilesView.thumbnailsWidth - maxX)
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        let docSize = scrollView.documentView!.frame.size
        thumbnailOverView.frame = CGRect(origin: .zero, size: docSize)
        thumbnailUnderLayer.frame = CGRect(origin: .zero, size: docSize)
    }

    private func searchBarHeight() -> CGFloat {
        let fitting = searchField.fittingSize.height
        if fitting > 0 {
            return ceil(fitting)
        }
        return ceil(searchField.cell?.cellSize.height ?? 30)
    }

    private func appIconsBottomViewportPadding(_ maxY: CGFloat, _ heightMax: CGFloat, _ labelHeight: CGFloat) -> CGFloat {
        guard Preferences.appearanceStyle == .appIcons, maxY > heightMax else { return 0 }
        return max(0, Appearance.windowPadding - labelHeight)
    }

    func centerRows(_ maxX: CGFloat) {
        for row in rows where !row.isEmpty {
            guard App.app.appIsBeingUsed else { return }
            let rowWidth = Appearance.interCellPadding + row.reduce(CGFloat(0)) { $0 + $1.frame.size.width + Appearance.interCellPadding }
            let offset = ((maxX - rowWidth) / 2).rounded()
            if offset > 0 {
                for view in row {
                    view.frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
                }
            }
        }
    }

    private func highlightStartView() {
        if Windows.selectedWindow() != nil {
            TilesView.highlight(Windows.selectedWindowIndex)
        } else {
            thumbnailUnderLayer.updateHighlight(focusedView: nil, hoveredView: nil)
            thumbnailOverView.hideWindowControls()
        }
        if let hoveredWindowIndex = Windows.hoveredWindowIndex,
           hoveredWindowIndex >= 0,
           hoveredWindowIndex < Windows.list.count,
           Windows.shouldDisplay(Windows.list[hoveredWindowIndex]) {
            TilesView.highlight(hoveredWindowIndex)
            if thumbnailOverView.isShowingWindowControls {
                thumbnailOverView.showWindowControls(for: TilesView.recycledViews[hoveredWindowIndex])
            }
        } else {
            thumbnailOverView.hideWindowControls()
        }
    }

    func clearNeedsLayout() {
        var views = [NSView]()
        if let contentView { views.append(contentView as NSView) }
        views.append(searchField)
        if let scrollView {
            views.append(scrollView)
            views.append(scrollView.contentView)
            if let documentView = scrollView.documentView { views.append(documentView) }
        }
        for view in views {
            view.needsLayout = false
            view.needsDisplay = false
            view.needsUpdateConstraints = false
        }
    }

    struct LayoutCache {
        var labelHeight = CGFloat(0)
        var iconWidth = CGFloat(0)
        var iconHeight = CGFloat(0)
        var comfortableReadabilityWidth: CGFloat?
    }

    
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    var isCurrentlyScrolling = false

    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
        documentView!.wantsLayer = true
        drawsBackground = false
        hasVerticalScroller = true
        verticalScrollElasticity = .none
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        observeScrollingEvents()
    }

    private func observeScrollingEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingStarted), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingEnded), name: NSScrollView.didEndLiveScrollNotification, object: nil)
    }

    @objc private func scrollingStarted() { isCurrentlyScrolling = true }
    @objc private func scrollingEnded() { isCurrentlyScrolling = false }

    /// holding shift and using the scrolling wheel will generate a horizontal movement
    /// shift can be part of shortcuts so we force shift scrolls to be vertical
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) && event.scrollingDeltaY == 0 {
            let cgEvent = event.cgEvent!
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 0)
            super.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
    // Prevent AppKit from recursively marking all NSControl subviews as needsDisplay during makeKeyAndOrderFront
    // Titles, Icons, and Traffic Icons would otherwise take lots of resource to update
    // We update everything explicitly, so this can be disabled
    @objc func _windowChangedKeyState() {}
}


enum Direction {
    case right
    case left
    case leading
    case trailing
    case up
    case down

    func step() -> Int {
        if self == .left {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? -1 : 1
        } else if self == .right {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? 1 : -1
        }
        return self == .leading ? 1 : -1
    }
}
