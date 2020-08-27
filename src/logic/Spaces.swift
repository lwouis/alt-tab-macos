import Cocoa

class Spaces {
    static var currentSpaceId = CGSSpaceID(1)
    static var currentSpaceIndex = SpaceIndex(1)
    static var isSingleSpace = true
    static var idsAndIndexes: [(CGSSpaceID, SpaceIndex)] = allIdsAndIndexes()

    static func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil, using: { _ in
            debugPrint("OS event", "activeSpaceDidChangeNotification")
            idsAndIndexes = allIdsAndIndexes()
            updateCurrentSpace()
            guard App.app.appIsBeingUsed else { return }
            App.app.reopenUi()
        })
    }

    static func refreshCurrentSpaceId() {
        // it seems that in some rare scenarios, some of these values are nil; we wrap to avoid crashing
        if let mainScreen = NSScreen.main,
           let uuid = Screen.uuid(mainScreen) {
            currentSpaceId = CGSManagedDisplayGetCurrentSpace(cgsMainConnectionId, uuid)
        }
    }

    static func initialDiscovery() {
        updateCurrentSpace()
        updateIsSingleSpace()
        observeSpaceChanges()
    }

    static func updateCurrentSpace() {
        refreshCurrentSpaceId()
        currentSpaceIndex = idsAndIndexes.first { (spaceId: CGSSpaceID, _) -> Bool in
            spaceId == currentSpaceId
        }?.1 ?? SpaceIndex(1)
        debugPrint("Current space", currentSpaceId)
    }

    static func allIdsAndIndexes() -> [(CGSSpaceID, SpaceIndex)] {
        return (CGSCopyManagedDisplaySpaces(cgsMainConnectionId) as! [NSDictionary])
            .map { (display: NSDictionary) -> [NSDictionary] in
                display["Spaces"] as! [NSDictionary]
            }
            .joined().enumerated()
            .map { (space: (offset: Int, element: NSDictionary)) -> (CGSSpaceID, SpaceIndex) in
                (space.element["id64"]! as! CGSSpaceID, space.offset + 1)
            }
    }

    static func otherSpaces() -> [CGSSpaceID] {
        return idsAndIndexes.filter { $0.0 != currentSpaceId }.map { $0.0 }
    }

    static func windowsInSpaces(_ spaceIds: [CGSSpaceID]) -> [CGWindowID] {
        var set_tags = UInt64(0)
        var clear_tags = UInt64(0)
        return CGSCopyWindowsWithOptionsAndTags(cgsMainConnectionId, 0, spaceIds as CFArray, 2, &set_tags, &clear_tags) as! [CGWindowID]
    }

    static func updateIsSingleSpace() {
        isSingleSpace = idsAndIndexes.count == 1
    }
}

typealias SpaceIndex = Int
