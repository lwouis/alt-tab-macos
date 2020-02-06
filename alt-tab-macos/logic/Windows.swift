import Cocoa

class Windows {
    // order in the array is important: most-recently-used elements are first
    static var list = [Window]()
    static var focusedWindowIndex = Array<Window>.Index(0)

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Array<Window>.Index) {
        focusedWindowIndex = focusedWindowIndex + step < 0 ? list.count - 1 : (focusedWindowIndex + step) % list.count
    }

    static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ destroyedWindowIndex: Array<Window>.Index) {
        if focusedWindowIndex <= destroyedWindowIndex {
            focusedWindowIndex -= 1
            return
        }
    }

    static func moveFocusedWindowIndexAfterWindowCreatedInBackground() {
        focusedWindowIndex += 1
    }

    static func updateSpaces() {
        let spacesMap = Spaces.allIdsAndIndexes()
        for window in list {
            let spaceIds = window.cgWindowId.spaces()
            guard spaceIds.count > 0 else { continue }
            if spaceIds.count > 1 {
                window.spaceId = Spaces.currentSpaceId
                window.spaceIndex = Spaces.currentSpaceIndex
                window.isOnAllSpaces = true
                continue
            }
            window.spaceId = spaceIds.first!
            window.spaceIndex = spacesMap.first { $0.0 == spaceIds.first! }!.1
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
        for window in list {
            window.refreshThumbnail()
        }
    }
}
