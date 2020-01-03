import Cocoa
import Foundation

class TrackedWindows {
    static var list = [TrackedWindow]()
    static var focusedWindowIndex = Int(0)

    static func focusedWindow() -> TrackedWindow? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func moveFocusedWindowIndex(_ step: Int) -> Int {
        return focusedWindowIndex + step < 0 ? list.count - 1 : (focusedWindowIndex + step) % list.count
    }

    static func refreshList(_ step: Int) {
        list.removeAll()
        focusedWindowIndex = 0
        let spaces = Spaces.allIdsAndIndexes()
        Spaces.currentSpaceId = CGSManagedDisplayGetCurrentSpace(cgsMainConnectionId, Screen.mainUuid())
        Spaces.currentSpaceIndex = spaces.first { $0.0 == Spaces.currentSpaceId }!.1
        filterAndAddToList(mapWindowsWithRankAndSpace(spaces))
        isSingleSpace()
        sortList()
    }

    private class func isSingleSpace() {
        let firstSpaceIndex = list[0].spaceIndex
        for window in list {
            if window.spaceIndex != firstSpaceIndex {
                Spaces.singleSpace = false
                return
            }
        }
        Spaces.singleSpace = true
    }

    private static func mapWindowsWithRankAndSpace(_ spaces: [(CGSSpaceID, SpaceIndex)]) -> [CGWindowID: (CGSSpaceID, SpaceIndex, WindowRank)] {
        var windowSpaceMap: [CGWindowID: (CGSSpaceID, SpaceIndex, WindowRank?)] = [:]
        for (spaceId, spaceIndex) in spaces {
            Spaces.windowsInSpaces([spaceId]).forEach {
                windowSpaceMap[$0] = (spaceId, spaceIndex, nil)
            }
        }
        Spaces.windowsInSpaces(spaces.map { $0.0 }).enumerated().forEach {
            windowSpaceMap[$0.element]!.2 = $0.offset
        }
        return windowSpaceMap as! [CGWindowID: (CGSSpaceID, SpaceIndex, WindowRank)]
    }

    private static func sortList() {
        list.sort(by: {
            if $0.rank == nil {
                return false
            }
            if $1.rank == nil {
                return true
            }
            return $0.rank! < $1.rank!
        })
    }

    private static func filterAndAddToList(_ windowsMap: [CGWindowID: (CGSSpaceID, SpaceIndex, WindowRank)]) {
        for cgWindow in CGWindow.windows(.optionAll) {
            guard let cgId = cgWindow.value(.number, CGWindowID.self),
                  let ownerPid = cgWindow.value(.ownerPID, pid_t.self),
                  cgWindow.isNotMenubarOrOthers(),
                  cgWindow.isReasonablyBig() else {
                continue
            }
            let (spaceId, spaceIndex, rank) = windowsMap[cgId] ?? (nil, nil, nil)
            if let axWindow = cgId.AXUIElement(ownerPid), axWindow.isActualWindow() {
                // window is in the current space
                if spaceId != nil {
                    list.append(TrackedWindow(cgWindow, cgId, ownerPid, false, axWindow, spaceId, spaceIndex, rank))
                }
                // window is minimized
                else if axWindow.isMinimized() {
                    list.append(TrackedWindow(cgWindow, cgId, ownerPid, true, axWindow, nil, nil, rank))
                }
            }
            // window is on another space
            else if spaceId != nil && spaceId != Spaces.currentSpaceId {
                list.append(TrackedWindow(cgWindow, cgId, ownerPid, false, nil, spaceId, spaceIndex, rank))
            }
        }
    }
}

typealias WindowRank = Int
