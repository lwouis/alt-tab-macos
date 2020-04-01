import Cocoa

class Windows {
    // order in the array is important: most-recently-used elements are first
    static var list = [Window]()
    static var previousFocusedWindowIndex = Array<Window>.Index(0)
    static var focusedWindowIndex = Array<Window>.Index(0)
    static var windowsInSubscriptionRetryLoop = [String]()

    static func updateFocusedWindowIndex(_ newValue: Array<Window>.Index) {
        previousFocusedWindowIndex = focusedWindowIndex
        focusedWindowIndex = newValue
        let focusedView = ThumbnailsView.recycledViews[focusedWindowIndex]
        ThumbnailsPanel.highlightCell(ThumbnailsView.recycledViews[previousFocusedWindowIndex], focusedView)
        App.app.thumbnailsPanel!.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
    }

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Array<Window>.Index) {
        updateFocusedWindowIndex(focusedWindowIndex + step < 0 ? list.count - 1 : (focusedWindowIndex + step) % list.count)
    }

    static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ destroyedWindowIndex: Array<Window>.Index) {
        if focusedWindowIndex <= destroyedWindowIndex {
            updateFocusedWindowIndex(max(focusedWindowIndex - 1, 0))
        }
    }

    static func moveFocusedWindowIndexAfterWindowCreatedInBackground(_ step: Int) {
        updateFocusedWindowIndex(focusedWindowIndex + step)
    }

    static func updateSpaces() {
        let spacesMap = Spaces.allIdsAndIndexes()
        list.forEachAsync { window in
            let spaceIds = window.cgWindowId.spaces()
            if spaceIds.count == 1 {
                window.spaceId = spaceIds.first!
                window.spaceIndex = spacesMap.first { $0.0 == spaceIds.first! }!.1
            } else if spaceIds.count > 1 {
                window.spaceId = Spaces.currentSpaceId
                window.spaceIndex = Spaces.currentSpaceIndex
                window.isOnAllSpaces = true
            }
        }
    }

    static func sortByLevel() {
        var windowLevelMap = [CGWindowID: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces([Spaces.currentSpaceId]).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        var sortedTuples = Windows.list.map { (windowLevelMap[$0.cgWindowId], $0) }
        sortedTuples.sort(by: {
            if $0.0 == nil {
                return false
            }
            if $1.0 == nil {
                return true
            }
            return $0.0! < $1.0!
        })
        Windows.list = sortedTuples.map { $0.1 }
    }

    static func refreshAllThumbnails() {
        list.forEachAsync { window in
            window.refreshThumbnail()
        }
    }

    static func refreshAllExistingThumbnails() {
        refreshAllThumbnails()
        guard App.app.uiWorkShouldBeDone else { return }
        list.enumerated().forEach {
            let newImage = $0.element.thumbnail
            let view = ThumbnailsView.recycledViews[$0.offset].thumbnail
            if view.image != newImage {
                let oldSize = view.image!.size
                view.image = newImage
                view.image!.size = oldSize
                view.frame.size = oldSize
            }
        }
    }
}
