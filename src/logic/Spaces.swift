import Cocoa

class Spaces {
    static var currentSpaceId = CGSSpaceID(1)
    static var currentSpaceIndex = SpaceIndex(1)
    static var visibleSpaces = [CGSSpaceID]()
    static var screenSpacesMap = [ScreenUuid: [CGSSpaceID]]()
    static var idsAndIndexes = [(CGSSpaceID, SpaceIndex)]()

    static func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil, using: { _ in
            debugPrint("OS event", "activeSpaceDidChangeNotification")
            refreshAllIdsAndIndexes()
            updateCurrentSpace()
            // if UI was kept open during Space transition, the Spaces may be obsolete; we refresh them
            Windows.list.forEachAsync { $0.updatesWindowSpace() }
            // from macos 12.2 beta onwards, we can't get other-space windows; grabbing windows when switching spaces mitigates the issue
            Applications.manuallyUpdateWindows()
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil, using: { _ in
            debugPrint("OS event", "didChangeScreenParametersNotification")
            refreshAllIdsAndIndexes()
        })
    }

    static func refreshCurrentSpaceId() {
        // it seems that in some rare scenarios, some of these values are nil; we wrap to avoid crashing
        if let mainScreen = NSScreen.main,
           let uuid = mainScreen.uuid() {
            currentSpaceId = CGSManagedDisplayGetCurrentSpace(cgsMainConnectionId, uuid)
        }
    }

    static func initialDiscovery() {
        refreshAllIdsAndIndexes()
        updateCurrentSpace()
        observeSpaceChanges()
    }

    static func updateCurrentSpace() {
        refreshCurrentSpaceId()
        currentSpaceIndex = idsAndIndexes.first { (spaceId: CGSSpaceID, _) -> Bool in
            spaceId == currentSpaceId
        }?.1 ?? SpaceIndex(1)
        debugPrint("Current space", currentSpaceId)
    }

    static func refreshAllIdsAndIndexes() -> Void {
        idsAndIndexes.removeAll()
        screenSpacesMap.removeAll()
        visibleSpaces.removeAll()
        var spaceIndex = SpaceIndex(1)
        (CGSCopyManagedDisplaySpaces(cgsMainConnectionId) as! [NSDictionary]).forEach { (screen: NSDictionary) in
            var display = screen["Display Identifier"] as! ScreenUuid
            if display as String == "Main", let mainUuid = NSScreen.main?.uuid() {
                display = mainUuid
            }
            (screen["Spaces"] as! [NSDictionary]).forEach { (space: NSDictionary) in
                let spaceId = space["id64"] as! CGSSpaceID
                idsAndIndexes.append((spaceId, spaceIndex))
                screenSpacesMap[display, default: []].append(spaceId)
                spaceIndex += 1
            }
            visibleSpaces.append((screen["Current Space"] as! NSDictionary)["id64"] as! CGSSpaceID)
        }
    }

    static func otherSpaces() -> [CGSSpaceID] {
        return idsAndIndexes.filter { $0.0 != currentSpaceId }.map { $0.0 }
    }

    static func windowsInSpaces(_ spaceIds: [CGSSpaceID], _ includeInvisible: Bool = true) -> [CGWindowID] {
        var set_tags = ([] as CGSCopyWindowsTags).rawValue
        var clear_tags = ([] as CGSCopyWindowsTags).rawValue
        var options = [.screenSaverLevel1000] as CGSCopyWindowsOptions
        if includeInvisible {
            options = [options, .invisible1, .invisible2]
        }
        return CGSCopyWindowsWithOptionsAndTags(cgsMainConnectionId, 0, spaceIds as CFArray, options.rawValue, &set_tags, &clear_tags) as! [CGWindowID]
    }

    static func isSingleSpace() -> Bool {
        return idsAndIndexes.count == 1
    }
}

typealias SpaceIndex = Int
