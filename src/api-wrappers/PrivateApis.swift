// Private APIs are APIs that we can build the app against, but they are not supported or documented by Apple
// We can see their names as symbols in the SDK (see https://github.com/lwouis/MacOSX-SDKs)
// However their full signature is a best-effort of retro-engineering
// Very little information is available about private APIs. I tried to document them as much as possible here
// Some links:
// * Webkit repo: https://github.com/WebKit/webkit/blob/master/Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h
// * Alt-tab-macos issue: https://github.com/lwouis/alt-tab-macos/pull/87#issuecomment-558624755
// * Github repo with retro-engineered internals: https://github.com/NUIKit/CGSInternal

import Cocoa

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    // on a retina display, 1px is spread on 4px, so nominalResolution is 1/4 of bestResolution
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
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
func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: inout CGWindowID, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> Unmanaged<CFArray>

// returns an array of displays (as NSDictionary) -> each having an array of spaces (as NSDictionary) at the "Spaces" key; each having a space ID (as UInt64) at the "id64" key
// * macOS 10.10+
// /!\ only returns correct values if the user has checked the checkbox in Preferences > Mission Control > "Displays have separate Spaces"
// See this example with 2 screens (1 laptop internal + 1 external):
// * Output with "Displays have separate Spaces" checked:
//   [{
//       "Current Space" =     {
//           ManagedSpaceID = 4;
//           id64 = 4;
//           type = 0;
//           uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//       };
//       "Display Identifier" = "6FBB92D9-84CE-8D20-C114-3B1052DD9529";
//       Spaces =     (
//           {
//               ManagedSpaceID = 4;
//               id64 = 4;
//               type = 0;
//               uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//           }
//       );
//   }, {
//       "Current Space" =     {
//           ManagedSpaceID = 5;
//           id64 = 5;
//           type = 0;
//           uuid = "BE05AFA2-B253-4199-B39E-A8E77CD4851B";
//       };
//       "Display Identifier" = "BB2327F9-3D4F-FD8F-A0EA-B9745A0B818F";
//       Spaces =     (
//           {
//               ManagedSpaceID = 5;
//               id64 = 5;
//               type = 0;
//               uuid = "BE05AFA2-B253-4199-B39E-A8E77CD4851B";
//           }
//       );
//   }]
// * Output with "Displays have separate Spaces" unchecked:
//   [{
//       "Current Space" =     {
//           ManagedSpaceID = 4;
//           id64 = 4;
//           type = 0;
//           uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//       };
//       "Display Identifier" = Main;
//       Spaces =     (
//           {
//               ManagedSpaceID = 4;
//               id64 = 4;
//               type = 0;
//               uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
//           }
//       );
//   }]
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

struct CGSCopyWindowsOptions: OptionSet {
    let rawValue: Int
    static let invisible1 = CGSCopyWindowsOptions(rawValue: 1 << 0)
    // retrieves windows when their app is assigned to All Spaces, and windows at ScreenSaver level 1000
    static let screenSaverLevel1000 = CGSCopyWindowsOptions(rawValue: 1 << 1)
    static let invisible2 = CGSCopyWindowsOptions(rawValue: 1 << 2)
    static let unknown1 = CGSCopyWindowsOptions(rawValue: 1 << 3)
    static let unknown2 = CGSCopyWindowsOptions(rawValue: 1 << 4)
    static let desktopIconWindowLevel2147483603 = CGSCopyWindowsOptions(rawValue: 1 << 5)
}

struct CGSCopyWindowsTags: OptionSet {
    let rawValue: Int
    static let level0 = CGSCopyWindowsTags(rawValue: 1 << 0)
    static let noTitleMaybePopups = CGSCopyWindowsTags(rawValue: 1 << 1)
    static let unknown1 = CGSCopyWindowsTags(rawValue: 1 << 2)
    static let mainMenuWindowAndDesktopIconWindow = CGSCopyWindowsTags(rawValue: 1 << 3)
    static let unknown2 = CGSCopyWindowsTags(rawValue: 1 << 4)
}

// returns an array of window IDs (as UInt32) for the space(s) provided as `spaces`
// the elements of the array are ordered by the z-index order of the windows in each space, with some exceptions where spaces mix
// * macOS 10.10+
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int, _ setTags: inout Int, _ clearTags: inout Int) -> CFArray

// returns the current space ID on the provided display UUID
// * macOS 10.10+
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: ScreenUuid) -> CGSSpaceID

// adds the provided windows to the provided spaces
// * macOS 10.10-12.2
@_silgen_name("CGSAddWindowsToSpaces")
func CGSAddWindowsToSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray) -> Void

// remove the provided windows from the provided spaces
// * macOS 10.10-12.2
@_silgen_name("CGSRemoveWindowsFromSpaces")
func CGSRemoveWindowsFromSpaces(_ cid: CGSConnectionID, _ windows: NSArray, _ spaces: NSArray) -> Void

// focuses the front process
// * macOS 10.12+
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID, _ mode: SLPSMode.RawValue) -> CGError

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
// the return value will be the same during the app lifetime; it will not reflect the actual status of the checkbox
@_silgen_name("SLSRequestScreenCaptureAccess") @discardableResult
func SLSRequestScreenCaptureAccess() -> UInt8

// for some reason, these attributes are missing from AXAttributeConstants
let kAXFullscreenAttribute = "AXFullScreen"
let kAXStatusLabelAttribute = "AXStatusLabel"

// for some reason, these attributes are missing from AXRoleConstants
let kAXDocumentWindowSubrole = "AXDocumentWindow"

// mission control private notifications
enum MissionControlState: String, CaseIterable {
    case showAllWindows = "AXExposeShowAllWindows"
    case showFrontWindows = "AXExposeShowFrontWindows"
    case showDesktop = "AXExposeShowDesktop"
    case inactive = "AXExposeExit"
}

enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6 // see keyAboveTabDependingOnInputSource
}

// enables/disables a symbolic hotkeys. These are system shortcuts such as command+tab or Spotlight
// it is possible to find all the existing hotkey IDs by using CGSGetSymbolicHotKeyValue on the first few hundred numbers
// note: the effect of enabling/disabling persists after the app is quit
@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey.RawValue, _ isEnabled: Bool) -> CGError

func setNativeCommandTabEnabled(_ isEnabled: Bool, _ hotkeys: [CGSSymbolicHotKey] = CGSSymbolicHotKey.allCases) {
    for hotkey in hotkeys {
        CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, isEnabled)
    }
}

// returns info about a given psn
// * macOS 10.9-10.15 (officially removed in 10.9, but available as a private API still)
@_silgen_name("GetProcessInformation") @discardableResult
func GetProcessInformation(_ psn: inout ProcessSerialNumber, _ info: inout ProcessInfoRec) -> OSErr

// returns the psn for a given pid
// * macOS 10.9-10.15 (officially removed in 10.9, but available as a private API still)
@_silgen_name("GetProcessForPID") @discardableResult
func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

// get the display UUID with the active menubar (other menubar are dimmed)
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> ScreenUuid
