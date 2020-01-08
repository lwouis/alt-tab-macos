import Cocoa
import Foundation

class Windows {
    static var listRecentlyUsedFirst = [Window]()
    static var focusedWindowIndex = Array<Window>.Index(0)

    static func focusedWindow() -> Window? {
        return listRecentlyUsedFirst.count > focusedWindowIndex ? listRecentlyUsedFirst[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Array<Window>.Index) {
        focusedWindowIndex = focusedWindowIndex + step < 0 ? listRecentlyUsedFirst.count - 1 : (focusedWindowIndex + step) % listRecentlyUsedFirst.count
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
        for window in listRecentlyUsedFirst {
            guard let spaceId = (CGSCopySpacesForWindows(cgsMainConnectionId, CGSSpaceMask.all.rawValue, [window.cgWindowId] as CFArray) as! [CGSSpaceID]).first else { continue }
            window.spaceId = spaceId
            window.spaceIndex = spacesMap.first { $0.0 == spaceId }!.1
        }
    }

    static func sortByLevel() {
        var windowLevelMap = [CGWindowID: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces([Spaces.currentSpaceId]).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        var sortedTuples = Windows.listRecentlyUsedFirst.map { (windowLevelMap[$0.cgWindowId], $0) }
        sortedTuples.sort(by: {
            if $0.0 == nil {
                return false
            }
            if $1.0 == nil {
                return true
            }
            return $0.0! < $1.0!
        })
        Windows.listRecentlyUsedFirst = sortedTuples.map { $0.1 }
    }

    static func refreshAllThumbnails() {
        for window in listRecentlyUsedFirst {
            window.refreshThumbnail()
        }
    }
}

extension Array where Element == Window {
    func firstIndexThatMatches(_ element: AXUIElement) -> Self.Index? {
        // `CFEqual` is safer than comparing `CGWindowID` because it will succeed even if the window is deallocated
        // by the OS, in which case the `CGWindowID` will be `-1`
        return firstIndex(where: { CFEqual($0.axUiElement, element) })
    }

    func firstWindowThatMatches(_ element: AXUIElement) -> Window? {
        guard let index = firstIndexThatMatches(element) else { return nil }
        return self[index]
    }
}
