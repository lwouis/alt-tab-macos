import Cocoa

class Windows {
    // order in the array is important: most-recently-used elements are first
    static var list = [Window]()
    static var previousFocusedWindowIndex = Int(0)
    static var focusedWindowIndex = Int(0)
    static var windowsInSubscriptionRetryLoop = [String]()

    static func updateFocusedWindowIndex(_ newIndex: Int) {
        previousFocusedWindowIndex = focusedWindowIndex
        focusedWindowIndex = newIndex
        let focusedView = ThumbnailsView.recycledViews[focusedWindowIndex]
        ThumbnailsPanel.highlightCell(ThumbnailsView.recycledViews[previousFocusedWindowIndex], focusedView)
        App.app.thumbnailsPanel!.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
    }

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Int) {
        var iterations = 0
        var targetIndex = focusedWindowIndex
        repeat {
            let next = (targetIndex + step) % list.count
            targetIndex = next < 0 ? list.count + next : next
            iterations += 1
        } while !list[targetIndex].shouldShowTheUser && iterations <= list.count
        updateFocusedWindowIndex(targetIndex)
    }

    static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ destroyedWindowIndex: Int) {
        if focusedWindowIndex > destroyedWindowIndex {
            cycleFocusedWindowIndex(-1)
        }
    }

    static func updateSpaces() {
        Spaces.updateIsSingleSpace()
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refreshCurrentSpaceId()
        let spacesMap = Spaces.idsAndIndexes
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

    static func refreshWhichWindowsToShowTheUser(_ screen: NSScreen) {
        var screenFrameInQuartzCoordinates = screen.frame
        screenFrameInQuartzCoordinates.origin.y = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(screen.frame)
        let activeApp = NSWorkspace.shared.frontmostApplication
        Windows.list.forEach {
            $0.shouldShowTheUser = !(!Preferences.showMinimizedWindows && $0.isMinimized) &&
                    !(!Preferences.showHiddenWindows && $0.isHidden) &&
                    !(Preferences.appsToShow == .active && $0.application.runningApplication != activeApp) &&
                    !(Preferences.spacesToShow == .active && $0.spaceId != Spaces.currentSpaceId) &&
                    !(Preferences.screensToShow == .showingAltTab && $0.axUiElement.position().map { p in !screenFrameInQuartzCoordinates.contains(p) } ?? true)
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
