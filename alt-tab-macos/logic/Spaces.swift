import Cocoa
import Foundation

class Spaces {
    static var currentSpaceId = CGSSpaceID(1)
    static var currentSpaceIndex = SpaceIndex(1)
    static var visitedSpaces = [CGSSpaceID: Bool]()
    static var isSingleSpace = true

    static func observeSpaceChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil, using: { _ in
            updateCurrentSpace()
            guard visitedSpaces[Spaces.currentSpaceId] == nil else { return }
            visitedSpaces[Spaces.currentSpaceId] = true
            // when visiting a space for the first time, we review windows that we could not gather before the visit, from the other space
            Applications.reviewRunningApplicationsWindows()
        })
    }

    static func updateCurrentSpace() {
        Spaces.currentSpaceId = CGSManagedDisplayGetCurrentSpace(cgsMainConnectionId, Screen.mainUuid())
        Spaces.currentSpaceIndex = allIdsAndIndexes().first { $0.0 == Spaces.currentSpaceId }!.1
        debugPrint("current space", Spaces.currentSpaceId)
    }

    static func updateInitialSpace() {
        updateCurrentSpace()
        visitedSpaces[Spaces.currentSpaceId] = true
    }

    static func allIdsAndIndexes() -> [(CGSSpaceID, SpaceIndex)] {
        return (CGSCopyManagedDisplaySpaces(cgsMainConnectionId) as! [NSDictionary])
                .map { return $0["Spaces"] }.joined().enumerated()
                .map { (($0.element as! NSDictionary)["id64"]! as! CGSSpaceID, $0.offset + 1) }
    }

    static func windowsInSpaces(_ spaceIds: [CGSSpaceID]) -> [CGWindowID] {
        var set_tags = UInt64(0)
        var clear_tags = UInt64(0)
        return CGSCopyWindowsWithOptionsAndTags(cgsMainConnectionId, 0, spaceIds as CFArray, 2, &set_tags, &clear_tags) as! [CGWindowID]
    }

    static func updateIsSingleSpace() {
        isSingleSpace = allIdsAndIndexes().count == 1
    }
}

typealias SpaceIndex = Int
