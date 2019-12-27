import Cocoa
import Foundation

class TrackedWindow {
    var cgWindow: CGWindow
    var ownerPid: pid_t
    var id: CGWindowID
    var title: String
    var thumbnail: NSImage?
    var icon: NSImage?
    var app: NSRunningApplication?
    var axWindow: AXUIElement?
    var isMinimized: Bool
    var spaceId: CGSSpaceID?
    var spaceIndex: SpaceIndex?
    var rank: WindowRank?

    init(_ cgWindow: CGWindow, _ cgId: CGWindowID, _ ownerPid: pid_t, _ isMinimized: Bool, _ axWindow: AXUIElement?, _ spaceId: CGSSpaceID?, _ spaceIndex: SpaceIndex?, _ rank: WindowRank?) {
        self.cgWindow = cgWindow
        self.id = cgId
        self.ownerPid = ownerPid
        let cgTitle = cgWindow.value(.name, String.self)
        let cgOwnerName = cgWindow.value(.ownerName, String.self)
        // for some reason Google Chrome uses a unicode 0-width no-break space character in their empty window title
        self.title = cgTitle != nil && cgTitle != "" && cgTitle != "﻿" ? cgTitle! : cgOwnerName ?? ""
        self.app = NSRunningApplication(processIdentifier: ownerPid)
        self.icon = self.app?.icon
        if let cgImage = cgId.screenshot() {
            self.thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        self.axWindow = axWindow
        self.isMinimized = isMinimized
        self.spaceId = spaceId
        // System Preferences windows appear on all spaces, so we make them the current space
        self.spaceIndex = app?.bundleIdentifier == "com.apple.systempreferences" ? Spaces.currentSpaceIndex : spaceIndex
        self.rank = rank
    }

    func focus() {
        if axWindow == nil {
            axWindow = id.AXUIElementOfOtherSpaceWindow(ownerPid)
        }
        axWindow?.focus(id)
    }
}
