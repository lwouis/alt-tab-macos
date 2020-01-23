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
            Applications.observeNewWindows()
            let app = App.shared as! App
            guard app.appIsBeingUsed else { return }
            app.reopenUi()
        })
    }

    static func initialDiscovery() {
        updateCurrentSpace()
        updateIsSingleSpace()
        observeSpaceChanges()
    }

    static func updateCurrentSpace() {
        currentSpaceId = CGSManagedDisplayGetCurrentSpace(cgsMainConnectionId, Screen.mainUuid())
        currentSpaceIndex = allIdsAndIndexes().first { $0.0 == currentSpaceId }!.1
        debugPrint("Current space", currentSpaceId)
    }

    static func allIdsAndIndexes() -> [(CGSSpaceID, SpaceIndex)] {
        return (CGSCopyManagedDisplaySpaces(cgsMainConnectionId) as! [NSDictionary])
                .map { return $0["Spaces"] }.joined().enumerated()
                .map { (($0.element as! NSDictionary)["id64"]! as! CGSSpaceID, $0.offset + 1) }
    }

    static func otherSpaces() -> [CGSSpaceID] {
        return allIdsAndIndexes().filter { $0.0 != currentSpaceId }.map { $0.0 }
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
