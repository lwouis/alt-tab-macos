import Cocoa
import Foundation

// Private APIs are APIs that we can build the app against, but they are not supported or documented by Apple
// We can see their names as symbols in the SDK (see https://github.com/lwouis/MacOSX-SDKs)
// However their full signature is a best-effort of retro-engineering
// Very little information is available about private APIs. I tried to document them as much as possible here
// Some links:
// * Webkit repo: https://github.com/WebKit/webkit/blob/master/Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h
// * Alt-tab-macos issue: https://github.com/lwouis/alt-tab-macos/pull/87#issuecomment-558624755

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let windowCaptureNominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 0x0200)
    static let captureIgnoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 0x0800)
}

enum SLPSMode: UInt32 {
    case allWindows = 0x100
    case userGenerated = 0x200
    case noWindows = 0x400
}

// returns the connection to the WindowServer. This connection ID is required when calling other APIs
// * macOS 10.10+
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// returns an array of CGImage of the windows which ID is given as `windowList`. `windowList` is supposed to be an array of IDs but in my test on High Sierra, the function ignores other IDs than the first, and always returns the screenshot of the first window in the array
// * performance: the `HW` in the name seems to imply better performance, and it was observed by some contributors that it seems to be faster (see https://github.com/lwouis/alt-tab-macos/issues/45) than other methods
// * quality: medium
// * minimized windows: yes
// * windows in other spaces: yes
// * offscreen content: no
// * macOS 10.10+
@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: inout CGWindowID, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> CFArray

// returns the CGImage of the window which ID is given in `wid`
// * performance: a bit faster than `CGWindowListCreateImage`, but still less than `CGSHWCaptureWindowList`
// * quality: low
// * minimized windows: yes
// * windows in other spaces: yes
// * offscreen content: no
// * macOS 10.10+
@_silgen_name("CGSCaptureWindowsContentsToRectWithOptions") @discardableResult
func CGSCaptureWindowsContentsToRectWithOptions(_ cid: CGSConnectionID, _ wid: inout CGWindowID, _ windowOnly: Bool, _ rect: CGRect, _ options: CGSWindowCaptureOptions, _ image: inout CGImage) -> CGError

// returns the connection ID for the provided window
// * macOS 10.10+
@_silgen_name("CGSGetWindowOwner") @discardableResult
func CGSGetWindowOwner(_ cid: CGSConnectionID, _ wid: CGWindowID, _ windowCid: inout CGSConnectionID) -> CGError

// returns the PSN for the provided connection ID
// * macOS 10.10+
@_silgen_name("CGSGetConnectionPSN") @discardableResult
func CGSGetConnectionPSN(_ cid: CGSConnectionID, _ psn: inout ProcessSerialNumber) -> CGError

// returns an array of displays (as NSDictionary) -> each having an array of spaces (as NSDictionary) at the "Spaces" key; each having a space ID (as UInt64) at the "id64" key
// /!\ only returns correct values if the user has checked the checkbox in Preferences > Mission Control > "Displays have separate Spaces"
// * macOS 10.10+
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

// returns an array of window IDs (as UInt32) for the space(s) provided as `spaces`
// the elements of the array are ordered by the z-index order of the windows in each space, with some exceptions where spaces mix
// * macOS 10.10+
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: UInt32, _ spaces: CFArray, _ options: UInt32, _ setTags: inout UInt64, _ clearTags: inout UInt64) -> CFArray

// returns the current space ID on the provided display UUID
// * macOS 10.10+
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: CFString) -> CGSSpaceID

// adds the provided windows to the provided spaces
// * macOS 10.10+
@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray) -> Void

// remove the provided windows from the provided spaces
// * macOS 10.10+
@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray) -> Void

// returns the front process PSN
// * macOS 10.12+
@_silgen_name("_SLPSGetFrontProcess") @discardableResult
func _SLPSGetFrontProcess(_ psn: inout ProcessSerialNumber) -> OSStatus

// focuses the front process
// * macOS 10.12+
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID, _ mode: SLPSMode) -> CGError

// sends bytes to the WindowServer
// more context: https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
// * macOS 10.12+
@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: inout ProcessSerialNumber, _ bytes: inout UInt8) -> CGError

// returns the CGWindowID of the provided AXUIElement
// * macOS 10.10+
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: inout CGWindowID) -> AXError

// returns the provided CGWindow property for the provided CGWindowID
// * macOS 10.10+
@_silgen_name("CGSCopyWindowProperty") @discardableResult
func CGSCopyWindowProperty(_ cid: CGSConnectionID, _ wid: CGWindowID, _ property: CFString, _ value: inout CFTypeRef?) -> CGError

enum CGSSpaceMask: Int {
    case current = 5
    case other = 6
    case all = 7
}

// get the CGSSpaceIDs for the given windows (CGWindowIDs)
// * macOS 10.10+
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: CGSSpaceMask.RawValue, _ wids: CFArray) -> CFArray

// returns window level (see definition in CGWindowLevel.h) of provided window
// * macOS 10.10+
@_silgen_name("CGSGetWindowLevel") @discardableResult
func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ level: inout CGWindowLevel) -> CGError

// returns status of the checkbox in System Preferences > Security & Privacy > Privacy > Screen Recording
// returns 1 if checked or 0 if unchecked; also prompts the user the first time if unchecked
@_silgen_name("SLSRequestScreenCaptureAccess") @discardableResult
func SLSRequestScreenCaptureAccess() -> UInt8




// ------------------------------------------------------------
// below are some notes on some private APIs I experimented with
// ------------------------------------------------------------

//// returns true is the PSNs are the same
//// * deprecated in macOS 10.9, so we have to declare it to use it in Swift
//@_silgen_name("SameProcess")
//func SameProcess(_ psn1: inout ProcessSerialNumber, _ psn2: inout ProcessSerialNumber, _ same: inout DarwinBoolean) -> Void
//
//// returns the CGRect of a window
//// * performance: it seems that this function is faster than the public API AX calls to get a window bounds
//// * minimized windows: ?
//// * windows in other spaces: ?
//// * macOS 10.12+
//@_silgen_name("CGSGetWindowBounds") @discardableResult
//func CGSGetWindowBounds(_ cid: CGSConnectionID, _ wid: inout CGWindowID, _ frame: inout CGRect) -> CGError
//
//// * deprecated in macOS 10.9, so we have to declare it to use it in Swift
//@_silgen_name("GetProcessPID")
//func GetProcessPID(_ psn: inout ProcessSerialNumber, _ pid: inout pid_t) -> Void
//
//// crashed the app with SIGSEGV
//// * macOS 10.10+
//@_silgen_name("CGSGetWindowType") @discardableResult
//func CGSGetWindowType(_ wid: CGWindowID, _ type: inout UInt32) -> CGError
//
//// * macOS 10.12+
//@_silgen_name("CGSProcessAssignToSpace") @discardableResult
//func CGSProcessAssignToSpace(_ cid: CGSConnectionID, _ pid: pid_t, _ sid: CGSSpaceID) -> CGError
//
//// changes the active space for the display_ref (e.g. "Main"). This doesn't actually trigger the UI animation and switch to the space. It allows windows from that space to be manipulated (e.g. focused) from the current space. Very weird behaviour and graphical glitch will happen when triggering Mission Control
//// * macOS 10.10+
//@_silgen_name("CGSManagedDisplaySetCurrentSpace")
//func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ sid: CGSSpaceID) -> Void
//
//// show provided spaces on top of the current space. It show windows from the provided spaces in the current space. Very weird behaviour and graphical glitch will happen when triggering Mission Control
//// * macOS 10.10+
//@_silgen_name("CGSShowSpaces")
//func CGSShowSpaces(_ cid: CGSConnectionID, _ sids: NSArray) -> Void
//
//// hides provided spaces from the current space
//// * macOS 10.10+
//@_silgen_name("CGSHideSpaces")
//func CGSHideSpaces(_ cid: CGSConnectionID, _ sids: NSArray) -> Void

//
//// get space for window
//// * macOS 10.10+
//@_silgen_name("CGSGetWindowWorkspace") @discardableResult
//func CGSGetWindowWorkspace(_ cid: CGSConnectionID, _ wid: CGWindowID, _ workspace: [Int]) -> OSStatus
//
//// returns the space uuid. Not very useful
//// * macOS 10.10+
//@_silgen_name("CGSSpaceCopyName")
//func CGSSpaceCopyName(_ cid: CGSConnectionID, _ sid: CGSSpaceID) -> CFString
//
//enum CGSWindowOrderingMode: Int {
//    case orderAbove = 1 // Window is ordered above target.
//    case orderBelow = -1 // Window is ordered below target.
//    case orderOut = 0  // Window is removed from the on-screen window list.
//}
//
//// change window order. I tried with relativeToWindow=0, and place=.orderAbove, and it does nothing
//// * macOS 10.10+
//@_silgen_name("CGSOrderWindow") @discardableResult
//func CGSOrderWindow(_ cid: CGSConnectionID, _ win: CGWindowID, _ place: CGSWindowOrderingMode, relativeTo: CGWindowID /* can be NULL */) -> OSStatus
//
//// Get on-screen window counts and lists. With targetCID=1 -> returns []. With targetCID=0 -> crashes, with targetCID=cid -> crashes
//// * macOS 10.10+
//@_silgen_name("CGSGetWindowList") @discardableResult
//func CGSGetWindowList(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ count: Int, _ list: [Int], _ outCount: [Int]) -> OSStatus
//
//// per-workspace window counts and lists. Can't compile on macOS 10.14 ("Undefined symbol: _CGSGetWorkspaceWindowList"). There are references of this API on the internet, but it doesn't seem to appear in any SDK though
//// * macOS 10.10+
//@_silgen_name("CGSGetWorkspaceWindowList") @discardableResult
//func CGSGetWorkspaceWindowList(_ cid: CGSConnectionID, _ workspaceNumber: CGSSpaceID, _ count: Int, _ list: [Int], _ outCount: [Int]) -> OSStatus
//
//enum CGSSpaceType {
//    case user
//    case fullscreen
//    case system
//    case unknown
//}
//
//// get the CGSSpaceType for a given space. Maybe useful for fullscreen windows
//// * macOS 10.10+
//@_silgen_name("CGSSpaceGetType")
//func CGSSpaceGetType(_ connection: CGSConnectionID, _ space: CGSSpaceID) -> CGSSpaceType
//
//// assigns a process to all spaces. This creates weird behaviours where its windows are available from all spaces
//// * macOS 10.10+
//@_silgen_name("CGSProcessAssignToAllSpaces") @discardableResult
//func CGSProcessAssignToAllSpaces(_ cid: CGSConnectionID, _ pid: pid_t) -> CGError
//
//enum SpaceManagementMode: Int {
//    case separate = 1
//    case notSeparate = 0
//}
//
//// returns the status of the "Displays have separate Spaces" system Preference
//// * macOS 10.10+
//@_silgen_name("CGSGetSpaceManagementMode")
//func CGSGetSpaceManagementMode(_ cid: CGSConnectionID) -> SpaceManagementMode
//
//// The following function was ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
//func windowManagerDeferWindowRaise(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
//    var wid_ = wid
//    var psn_ = psn
//
//    var bytes = [UInt8](repeating: 0, count: 0xf8)
//    bytes[0x04] = 0xf8
//    bytes[0x08] = 0x0d
//    bytes[0x8a] = 0x09
//
//    memcpy(&bytes[0x3c], &wid_, MemoryLayout<UInt32>.size)
//    SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes)).pointee))
//}
//
//func windowManagerDeactivateWindow(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
//    var wid_ = wid
//    var psn_ = psn
//
//    var bytes = [UInt8](repeating: 0, count: 0xf8)
//    bytes[0x04] = 0xf8
//    bytes[0x08] = 0x0d
//    bytes[0x8a] = 0x02
//
//    memcpy(&bytes[0x3c], &wid_, MemoryLayout<UInt32>.size)
//    SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes)).pointee))
//}
//
//func windowManagerActivateWindow(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
//    var wid_ = wid
//    var psn_ = psn
//
//    var bytes = [UInt8](repeating: 0, count: 0xf8)
//    bytes[0x04] = 0xf8
//    bytes[0x08] = 0x0d
//    bytes[0x8a] = 0x01
//
//    memcpy(&bytes[0x3c], &wid_, MemoryLayout<UInt32>.size)
//    SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes)).pointee))
//}
//
//func psnEqual(_ psn1: ProcessSerialNumber, _ psn2: ProcessSerialNumber) -> Bool {
//    var psn1_ = psn1
//    var psn2_ = psn2
//
//    var same = DarwinBoolean(false)
//    SameProcess(&psn1_, &psn2_, &same)
//    return same == DarwinBoolean(true)
//}
//
//func windowIdToPsn(_ wid: CGWindowID) -> ProcessSerialNumber {
//    var elementConnection = UInt32(0)
//    CGSGetWindowOwner(cgsMainConnectionId, wid, &elementConnection)
//    var psn = ProcessSerialNumber()
//    CGSGetConnectionPSN(elementConnection, &psn)
//    return psn
//}
