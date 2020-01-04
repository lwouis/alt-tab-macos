import Cocoa
import Foundation

class TrackedWindow {
    var cgWindow: CGWindow
    var id: CGWindowID
    var title: String
    var thumbnail: NSImage?
    var icon: NSImage?
    var app: NSRunningApplication
    var axApp: AXUIElement
    var axWindow: AXUIElement?
    var isHidden: Bool
    var isMinimized: Bool
    var spaceId: CGSSpaceID?
    var spaceIndex: SpaceIndex?
    var rank: WindowRank?

    init(_ cgWindow: CGWindow, _ cgId: CGWindowID, _ app: NSRunningApplication, _ axApp: AXUIElement, _ isHidden: Bool, _ isMinimized: Bool, _ axWindow: AXUIElement?, _ spaceId: CGSSpaceID?, _ spaceIndex: SpaceIndex?, _ rank: WindowRank?) {
        self.cgWindow = cgWindow
        self.id = cgId
        let cgTitle = cgWindow.value(.name, String.self)
        let cgOwnerName = cgWindow.value(.ownerName, String.self)
        // for some reason Google Chrome uses a unicode 0-width no-break space character in their empty window title
        self.title = cgTitle != nil && cgTitle != "" && cgTitle != "﻿" ? cgTitle! : cgOwnerName ?? ""
        self.app = app
        self.axApp = axApp
        self.icon = self.app.icon
        if let cgImage = cgId.screenshot() {
            self.thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        self.axWindow = axWindow
        self.isHidden = isHidden
        self.isMinimized = isMinimized
        self.spaceId = spaceId
        self.spaceIndex = spaceIndex
        self.rank = rank
    }

    func focus() {
        let onCurrentSpace = axWindow != nil
        if !onCurrentSpace {
            axWindow = id.AXUIElementOfOtherSpaceWindow(axApp)
        }
        axWindow?.focus(id)
    }
}
