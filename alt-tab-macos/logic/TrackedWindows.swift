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
        if list.count > 0 {
            let firstSpaceIndex = list[0].spaceIndex
            for window in list {
                if window.spaceIndex != nil && window.spaceIndex != firstSpaceIndex {
                    Spaces.singleSpace = false
                    return
                }
            }
        }
        Spaces.singleSpace = true
    }

    private static func mapWindowsWithRankAndSpace(_ spaces: [(CGSSpaceID, SpaceIndex)]) -> WindowsMap {
        var windowSpaceMap: [CGWindowID: (CGSSpaceID, SpaceIndex, WindowRank?)] = [:]
        for (spaceId, spaceIndex) in spaces {
            Spaces.windowsInSpaces([spaceId]).forEach {
                windowSpaceMap[$0] = (spaceId, spaceIndex, nil)
            }
        }
        Spaces.windowsInSpaces(spaces.map { $0.0 }).enumerated().forEach {
            windowSpaceMap[$0.element]!.2 = $0.offset
        }
        return windowSpaceMap as! WindowsMap
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

    private static func filterAndAddToList(_ windowsMap: WindowsMap) {
        // order and short-circuit of checks in this method is important for performance
        for cgWindow in CGWindow.windows(.optionAll) {
            guard let cgId = cgWindow.value(.number, CGWindowID.self),
                  let ownerPid = cgWindow.value(.ownerPID, pid_t.self),
                  let app = NSRunningApplication(processIdentifier: ownerPid),
                  cgWindow.isNotMenubarOrOthers(),
                  cgWindow.isReasonablyBig() else {
                continue
            }
            let axApp = cgId.AXUIElementApplication(ownerPid)
            let (spaceId, spaceIndex, rank) = windowsMap[cgId] ?? (nil, nil, nil)
            if let (isMinimized, isHidden, axWindow) = filter(cgId, spaceId, app, axApp) {
                list.append(TrackedWindow(cgWindow, cgId, app, axApp, isHidden, isMinimized, axWindow, spaceId, spaceIndex, rank))
            }
        }
    }

    private static func filter(_ cgId: CGWindowID, _ spaceId: CGSSpaceID?, _ app: NSRunningApplication, _ axApp: AXUIElement) -> (Bool, Bool, AXUIElement?)? {
        // window is in another space
        if spaceId != nil && spaceId != Spaces.currentSpaceId {
            return (false, false, nil)
        }
        // window is in the current space, or is hidden/minimized
        if let axWindow = axApp.window(cgId), axWindow.isActualWindow() {
            if spaceId != nil {
                return (false, false, axWindow)
            }
            if app.isHidden {
                return (axWindow.isMinimized(), true, axWindow)
            }
            if axWindow.isMinimized() {
                return (true, false, axWindow)
            }
        }
        return nil
    }
}

typealias WindowRank = Int
typealias WindowsMap = [CGWindowID: (CGSSpaceID, SpaceIndex, WindowRank)]