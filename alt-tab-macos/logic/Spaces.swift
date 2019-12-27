import Cocoa
import Foundation

class Spaces {
    static var singleSpace = true
    static var currentSpaceId = CGSSpaceID(1)
    static var currentSpaceIndex = SpaceIndex(1)

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
}

typealias SpaceIndex = Int
