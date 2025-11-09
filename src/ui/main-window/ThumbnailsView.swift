import Cocoa
import Carbon.HIToolbox.Events

class ThumbnailsView {
    var scrollView: ScrollView!
    var contentView: EffectView!
    let searchField = NSSearchField(frame: .zero)
    // The search bar is only shown after the user initiates search (Tab or any key)
    var searchBarVisible = false
    var rows = [[ThumbnailView]]()
    static var recycledViews = [ThumbnailView]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)

    init() {
        scrollView = ScrollView()
        contentView = makeAppropriateEffectView()
        configureSearchField()
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        // TODO: think about this optimization more
        (1...20).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
    }

    func updateBackgroundView() {
        let newEffectView = makeAppropriateEffectView()
        scrollView.removeFromSuperview()
        searchField.removeFromSuperview()
        newEffectView.addSubview(searchField)
        newEffectView.addSubview(scrollView)
        contentView.superview?.replaceSubview(contentView, with: newEffectView)
        contentView = newEffectView
    }

    private func configureSearchField() {
        searchField.placeholderString = NSLocalizedString("Search windows", comment: "Search placeholder")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.cell?.controlSize = .regular
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
    }

    @objc private func searchFieldChanged() {
        Windows.searchQuery = searchField.stringValue
        App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
    }

    func focusSearchField() {
        // Make the search field first responder to allow immediate typing
        guard Preferences.showSearchBar || Preferences.anyKeyToSearchEnabled else { return }
        if !searchBarVisible {
            searchBarVisible = true
            // Re-layout to reserve space for the search bar before focusing it
            App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
        }
        App.app.thumbnailsPanel.makeFirstResponder(searchField)
        // While searching, suppress cycling/repeat to avoid unintended navigation
        App.app.forceDoNothingOnRelease = true
        KeyRepeatTimer.deactivateTimerForRepeatingKey(Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex))
        KeyRepeatTimer.deactivateTimerForRepeatingKey("previousWindowShortcut")
    }

    /// Move focus from the search field back to the current selection (thumbnail).
    /// Also re-enable cycling on key release.
    func exitSearchFocus() {
        App.app.forceDoNothingOnRelease = false
        let index = Windows.focusedWindowIndex
        if index < ThumbnailsView.recycledViews.count {
            App.app.thumbnailsPanel.makeFirstResponder(ThumbnailsView.recycledViews[index])
        }
    }

    private func openFirstFilteredWindow() {
        if let idx = Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) {
            // Stop cycling repeat before focusing a window to avoid re-opening or cycling
            let nextName = Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex)
            KeyRepeatTimer.deactivateTimerForRepeatingKey(nextName)
            KeyRepeatTimer.deactivateTimerForRepeatingKey("previousWindowShortcut")
            let window = Windows.list[idx]
            App.app.focusSelectedWindow(window)
        }
    }

    func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        NSScreen.updatePreferred()
        Appearance.update()
        // thumbnails are captured continuously. They will pick up the new size on the next cycle
        ThumbnailsPanel.updateMaxPossibleThumbnailSize()
        // app icons are captured once at launch; we need to manually update them if needed
        let old = ThumbnailsPanel.maxPossibleAppIconSize.width
        ThumbnailsPanel.updateMaxPossibleAppIconSize()
        if old != ThumbnailsPanel.maxPossibleAppIconSize.width {
            Applications.updateAppIcons()
        }
        updateBackgroundView()
        App.app.thumbnailsPanel.contentView = contentView
        for i in 0..<ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews[i] = ThumbnailView()
        }
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        if view.frame != NSRect.zero {
            view.drawHighlight()
        }
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [ThumbnailView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.focusedWindow()?.rowIndex {
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
        guard Windows.focusedWindowIndex < ThumbnailsView.recycledViews.count else { return }
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.focusedWindowIndex].frame
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
        guard let targetIndex = ThumbnailsView.recycledViews.firstIndex(of: targetView) else { return }
        Windows.updateFocusedAndHoveredWindowIndex(targetIndex)
    }

    func updateItemsAndLayout() {
        let widthMax = ThumbnailsPanel.maxThumbnailsWidth().rounded()
        if let (maxX, maxY, labelHeight) = layoutThumbnailViews(widthMax) {
            layoutParentViews(maxX, widthMax, maxY, labelHeight)
            if Preferences.alignThumbnails == .center {
                // Center against the effective content width in use (may be clamped to a minimum while filtering)
                centerRows(ThumbnailsView.thumbnailsWidth)
            }
            for row in rows {
                for (j, view) in row.enumerated() {
                    view.numberOfViewsInRow = row.count
                    view.isFirstInRow = j == 0
                    view.isLastInRow = j == row.count - 1
                    view.indexInRow = j
                }
            }
            highlightStartView()
        }
    }

    private func layoutThumbnailViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat)? {
        let labelHeight = ThumbnailsView.recycledViews.first!.label.fittingSize.height
        let height = ThumbnailView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? Appearance.interCellPadding : widthMax - Appearance.interCellPadding
        var currentX = startingX
        var currentY = Appearance.interCellPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + Appearance.interCellPadding
        var newViews = [ThumbnailView]()
        rows.removeAll(keepingCapacity: true)
        rows.append([ThumbnailView]())
        var index = 0
        while index < ThumbnailsView.recycledViews.count {
            guard App.app.appIsBeingUsed else { return nil }
            defer { index = index + 1 }
            let view = ThumbnailsView.recycledViews[index]
            if index < Windows.list.count {
                let window = Windows.list[index]
                guard Windows.shouldDisplay(window) else { continue }
                view.updateRecycledCellWithNewContent(window, index, height)
                let width = view.frame.size.width
                let projectedX = projectedWidth(currentX, width).rounded(.down)
                if needNewLine(projectedX, widthMax) {
                    currentX = startingX
                    currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedWidth(currentX, width).rounded(.down)
                    maxY = max(currentY + height + Appearance.interCellPadding, maxY)
                    rows.append([ThumbnailView]())
                } else {
                    view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                    currentX = projectedX
                    maxX = max(isLeftToRight ? currentX : widthMax - currentX, maxX)
                }
                rows[rows.count - 1].append(view)
                newViews.append(view)
                window.rowIndex = rows.count - 1
            } else {
                // release images from unused recycledViews; they take lots of RAM
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
                view.windowlessIcon.releaseImage()
            }
        }
        scrollView.documentView!.subviews = newViews
        return (maxX, maxY, labelHeight)
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
        let heightMax = ThumbnailsPanel.maxThumbnailsHeight()
        // Reserve space for the search bar at the top when enabled and visible
        let searchHeight: CGFloat = 28
        let searchBottomPadding: CGFloat = 8
        let searchEnabled = (Preferences.showSearchBar || Preferences.anyKeyToSearchEnabled) && searchBarVisible
        let searchTotalHeight = searchEnabled ? (searchHeight + searchBottomPadding) : 0
        let isFiltering = !Windows.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Effective content width/height: apply minimums while filtering
        let effectiveContentWidth = max(min(maxX, widthMax), isFiltering ? Appearance.minSearchPanelContentWidth : 0)
        let contentAreaHeightMax = max(0, heightMax - searchTotalHeight)
        let effectiveContentHeight = max(min(maxY, contentAreaHeightMax), isFiltering ? Appearance.minSearchPanelContentHeight : 0)
        ThumbnailsView.thumbnailsWidth = effectiveContentWidth
        // Limit the thumbnails area height by reserving space for search
        ThumbnailsView.thumbnailsHeight = effectiveContentHeight
        let frameWidth = effectiveContentWidth + Appearance.windowPadding * 2
        var frameHeight = effectiveContentHeight + Appearance.windowPadding * 2 + searchTotalHeight
        let originX = Appearance.windowPadding
        var originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
            originY = originY - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        scrollView.frame.size = NSSize(width: effectiveContentWidth, height: effectiveContentHeight)
        scrollView.frame.origin = CGPoint(x: originX, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        // Position search field at the top, inside padding
        searchField.isHidden = !searchEnabled
        if searchEnabled {
            searchField.frame.size = NSSize(width: effectiveContentWidth, height: searchHeight)
            searchField.frame.origin = CGPoint(x: originX, y: frameHeight - Appearance.windowPadding - searchHeight)
        }
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        if let existingTrackingArea = scrollView.trackingAreas.first {
            scrollView.removeTrackingArea(existingTrackingArea)
        }
        scrollView.addTrackingArea(NSTrackingArea(rect: scrollView.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: scrollView, userInfo: nil))
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = Appearance.interCellPadding
        var rowY = Appearance.interCellPadding
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return }
            guard Windows.shouldDisplay(window) else { continue }
            let view = ThumbnailsView.recycledViews[index]
            if view.frame.origin.y == rowY {
                rowWidth += view.frame.size.width + Appearance.interCellPadding
            } else {
                shiftRow(maxX, rowWidth, rowStartIndex, index)
                rowStartIndex = index
                rowWidth = Appearance.interCellPadding + view.frame.size.width + Appearance.interCellPadding
                rowY = view.frame.origin.y
            }
        }
        shiftRow(maxX, rowWidth, rowStartIndex, Windows.list.count)
    }

    private func highlightStartView() {
        ThumbnailsView.highlight(Windows.focusedWindowIndex)
        if let hoveredWindowIndex = Windows.hoveredWindowIndex {
            ThumbnailsView.highlight(hoveredWindowIndex)
        }
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            for i in rowStartIndex..<index {
                ThumbnailsView.recycledViews[i].frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
            }
        }
    }
}

extension ThumbnailsView: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField === searchField else { return }
        Windows.searchQuery = searchField.stringValue
        // On any text change, stop any repeat cycling
        KeyRepeatTimer.deactivateTimerForRepeatingKey(Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex))
        KeyRepeatTimer.deactivateTimerForRepeatingKey("previousWindowShortcut")
        App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            openFirstFilteredWindow()
            return true
        } else if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            // Let the user exit search with Tab/Backtab only when the Exit Search
            // shortcut is actually set to Tab/Backtab. Compare on keyCode/modifiers
            // to avoid brittle string glyph comparisons.
            if let atShortcut = ControlsTab.shortcuts["searchExitShortcut"]?.shortcut {
                // kVK_Tab and optional Shift for backtab
                if atShortcut.carbonKeyCode == kVK_Tab {
                    let hasShift = (atShortcut.carbonModifierFlags & UInt32(shiftKey)) != 0
                    let isBacktab = commandSelector == #selector(NSResponder.insertBacktab(_:))
                    if isBacktab == hasShift {
                        exitSearchFocus()
                        return true
                    }
                }
            }
            return false
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // ESC exits the panel even when search has focus
            App.app.hideUi()
            return true
        }
        return false
    }
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    var isCurrentlyScrolling = false
    var previousTarget: ThumbnailView?

    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
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

    @objc private func scrollingStarted() {
        isCurrentlyScrolling = true
    }

    @objc private func scrollingEnded() {
        isCurrentlyScrolling = false
    }

    private func resetHoveredWindow() {
        if let oldIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
            ThumbnailsView.recycledViews[oldIndex].showOrHideWindowControls(false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        previousTarget = nil
        resetHoveredWindow()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let documentView, !isCurrentlyScrolling && !ScrollwheelEvents.shouldBeEnabled else { return }
        let location = documentView.convert(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream, from: nil)
        let newTarget = findTarget(location)
        guard newTarget !== previousTarget else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let newTarget {
            previousTarget?.showOrHideWindowControls(false)
            newTarget.mouseMoved()
        } else {
            resetHoveredWindow()
        }
        previousTarget = newTarget
        CATransaction.commit()
    }

    private func findTarget(_ location: NSPoint) -> ThumbnailView? {
        for i in 0..<Windows.list.count {
            let view = ThumbnailsView.recycledViews[i]
            let frame = view.frame
            let expandedFrame = CGRect(x: frame.minX - (App.shared.userInterfaceLayoutDirection == .leftToRight ? 0 : 1), y: frame.minY, width: frame.width + 1, height: frame.height + 1)
            if expandedFrame.contains(location) {
                return view
            }
        }
        return nil
    }

    /// Checks whether the mouse pointer is within the padding area around a thumbnail.
    ///
    /// This is used to avoid gaps between thumbnail views where the mouse pointer might not be detected.
    ///
    /// @return `true` if the mouse pointer is within the padding area around a thumbnail; `false` otherwise.
    private func checkIfWithinInterPadding() -> Bool {
        if Preferences.appearanceStyle == .appIcons {
            let mouseLocation = App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream
            let mouseRect = NSRect(x: mouseLocation.x - Appearance.interCellPadding,
                y: mouseLocation.y - Appearance.interCellPadding,
                width: 2 * Appearance.interCellPadding,
                height: 2 * Appearance.interCellPadding)
            if let hoveredWindowIndex = Windows.hoveredWindowIndex {
                let thumbnail = ThumbnailsView.recycledViews[hoveredWindowIndex]
                let mouseRectInView = thumbnail.convert(mouseRect, from: nil)
                if thumbnail.bounds.intersects(mouseRectInView) {
                    return true
                }
            }
        }
        return false
    }

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
