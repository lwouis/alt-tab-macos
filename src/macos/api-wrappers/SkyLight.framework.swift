/*
 SkyLight is the private framework in charge of interacting with the Window Server
 If we link to SkyLight.framework, we can use these private functions
 Location: Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/PrivateFrameworks/SkyLight.framework
 */

import Darwin // dlopen/dlsym for SLSWindowIteratorGetBounds' C-ABI binding (see below)

let CGS_CONNECTION = CGSMainConnectionID()

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

struct CGSWindowCaptureOptions: OptionSet {
    let rawValue: UInt32
    static let ignoreGlobalClipShape = CGSWindowCaptureOptions(rawValue: 1 << 11)
    // on a retina display, 1px is spread on 4px, so nominalResolution is 1/4 of bestResolution
    static let nominalResolution = CGSWindowCaptureOptions(rawValue: 1 << 9)
    static let bestResolution = CGSWindowCaptureOptions(rawValue: 1 << 8)
    // when Stage Manager is enabled, screenshots can become skewed. This param gets us full-size screenshots regardless
    static let fullSize = CGSWindowCaptureOptions(rawValue: 1 << 19)
}

/// returns the connection to the WindowServer. This connection ID is required when calling other APIs
/// * macOS 10.10+
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

/// returns an array of CGImage of the windows which ID is given as `windowList`. `windowList` is supposed to be an array of IDs but in my test on High Sierra, the function ignores other IDs than the first, and always returns the screenshot of the first window in the array
/// * performance: the `HW` in the name seems to imply better performance, and it was observed by some contributors that it seems to be faster (see https://github.com/lwouis/alt-tab-macos/issues/45) than other methods
/// * quality: medium
/// * minimized windows: yes
/// * windows in other spaces: yes
/// * offscreen content: no
/// * macOS 10.10+
@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(_ cid: CGSConnectionID, _ windowList: UnsafeMutablePointer<CGWindowID>, _ windowCount: UInt32, _ options: CGSWindowCaptureOptions) -> Unmanaged<CFArray>

/// returns an array of displays (as NSDictionary) -> each having an array of spaces (as NSDictionary) at the "Spaces" key; each having a space ID (as UInt64) at the "id64" key
/// * macOS 10.10+
/// /!\ only returns correct values if the user has checked the checkbox in Preferences > Mission Control > "Displays have separate Spaces"
/// See this example with 2 screens (1 laptop internal + 1 external):
/// * Output with "Displays have separate Spaces" checked:
///   [{
///       "Current Space" =     {
///           ManagedSpaceID = 4;
///           id64 = 4;
///           type = 0;
///           uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
///       };
///       "Display Identifier" = "6FBB92D9-84CE-8D20-C114-3B1052DD9529";
///       Spaces =     (
///           {
///               ManagedSpaceID = 4;
///               id64 = 4;
///               type = 0;
///               uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
///           }
///       );
///   }, {
///       "Current Space" =     {
///           ManagedSpaceID = 5;
///           id64 = 5;
///           type = 0;
///           uuid = "BE05AFA2-B253-4199-B39E-A8E77CD4851B";
///       };
///       "Display Identifier" = "BB2327F9-3D4F-FD8F-A0EA-B9745A0B818F";
///       Spaces =     (
///           {
///               ManagedSpaceID = 5;
///               id64 = 5;
///               type = 0;
///               uuid = "BE05AFA2-B253-4199-B39E-A8E77CD4851B";
///           }
///       );
///   }]
/// * Output with "Displays have separate Spaces" unchecked:
///   [{
///       "Current Space" =     {
///           ManagedSpaceID = 4;
///           id64 = 4;
///           type = 0;
///           uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
///       };
///       "Display Identifier" = Main;
///       Spaces =     (
///           {
///               ManagedSpaceID = 4;
///               id64 = 4;
///               type = 0;
///               uuid = "6622AC87-2FD2-48E8-934D-F6EB303AC9BA";
///           }
///       );
///   }]
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

/// returns an array of window IDs (as UInt32) for the space(s) provided as `spaces`
/// the elements of the array are ordered by the z-index order of the windows in each space, with some exceptions where spaces mix
/// * macOS 10.10+
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int, _ setTags: UnsafeMutablePointer<Int>, _ clearTags: UnsafeMutablePointer<Int>) -> CFArray

/// returns the current space ID on the provided display UUID
/// * macOS 10.10+
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: CGSConnectionID, _ displayUuid: ScreenUuid) -> CGSSpaceID

/// returns the provided CGWindow property for the provided CGWindowID
/// * macOS 10.10+
@_silgen_name("CGSCopyWindowProperty") @discardableResult
func CGSCopyWindowProperty(_ cid: CGSConnectionID, _ wid: CGWindowID, _ property: CFString, _ value: UnsafeMutablePointer<CFTypeRef?>) -> CGError

enum CGSSpaceMask: Int {
    case current = 5
    case other = 6
    case all = 7
}

/// get the CGSSpaceIDs for the given windows (CGWindowIDs)
/// * macOS 10.10+
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: CGSSpaceMask.RawValue, _ wids: CFArray) -> CFArray

/// returns window level (see definition in CGWindowLevel.h) of provided window
/// * macOS 10.10+
@_silgen_name("CGSGetWindowLevel") @discardableResult
func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ level: UnsafeMutablePointer<CGWindowLevel>) -> CGError

/// returns status of the checkbox in System Preferences > Security & Privacy > Privacy > Screen Recording
/// returns 1 if checked or 0 if unchecked; also prompts the user the first time if unchecked
/// the return value will be the same during the app lifetime; it will not reflect the actual status of the checkbox
@_silgen_name("SLSRequestScreenCaptureAccess") @discardableResult
func SLSRequestScreenCaptureAccess() -> UInt8

/// enables/disables a symbolic hotkeys. These are system shortcuts such as command+tab or Spotlight
/// it is possible to find all the existing hotkey IDs by using CGSGetSymbolicHotKeyValue on the first few hundred numbers
/// note: the effect of enabling/disabling persists after the app is quit
@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey.RawValue, _ isEnabled: Bool) -> CGError

func setNativeCommandTabEnabled(_ isEnabled: Bool, _ hotkeys: [CGSSymbolicHotKey] = CGSSymbolicHotKey.allCases) {
    for hotkey in hotkeys {
        CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, isEnabled)
    }
}

/// get the display UUID with the active menubar (other menubar are dimmed)
@_silgen_name("CGSCopyActiveMenuBarDisplayIdentifier")
func CGSCopyActiveMenuBarDisplayIdentifier(_ cid: CGSConnectionID) -> ScreenUuid

/// Flags for `_SLPSSetFrontProcessWithOptions` (yabai's `kCPS*`). They pick which of the fronted
/// process's windows come forward, and whether the switch counts as user-initiated.
enum SLPSMode: UInt32 {
    case allWindows = 0x100    // bring all of the app's windows forward
    case userGenerated = 0x200 // mark the front-switch as user-initiated (what we pass; avoids suppression)
    case noWindows = 0x400     // front the process without raising any window (e.g. yabai fronting Finder)
}

/// focuses the front process
/// * macOS 10.12+
@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: SLPSMode.RawValue) -> CGError

/// Sets the front process for a SINGLE Space, from a normal connection (yabai uses it in
/// `window_manager_send_window_to_space`). Unlike `_SLPSSetFrontProcessWithOptions`, it doesn't set the
/// global front or touch other Spaces' front-window memory — so we use it to focus a window on the current
/// Space without clobbering other Spaces, which is the #4507 cross-Space bleed.
/// * macOS 10.10+
@_silgen_name("SLSSpaceSetFrontPSN") @discardableResult
func SLSSpaceSetFrontPSN(_ cid: CGSConnectionID, _ sid: CGSSpaceID, _ psn: ProcessSerialNumber) -> CGError

/// sends bytes to the WindowServer
/// more context: https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
/// * macOS 10.12+
@_silgen_name("SLPSPostEventRecordTo") @discardableResult
func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

/// Byte layout of the `CGSEventRecord` posted in `makeKeyWindow` to make another app's window key.
/// Offsets and field meanings are reverse-engineered from CGSInternal's CGSEvent.h:
/// https://github.com/NUIKit/CGSInternal/blob/master/CGSEvent.h
private enum MakeKeyWindowEvent {
    /// Bytes we allocate. The record itself is `recordLength` (0xf8) bytes; we allocate a little more,
    /// zeroed, because on macOS 14.7.4+ the WindowServer's `CGSEncodeEventRecord` reads past the record
    /// and would otherwise SIGABRT on out-of-bounds heap garbage
    /// (https://github.com/karinushka/paneru/issues/123). yabai allocates the same 0x100.
    static let bufferSize = 0x100
    /// 0x04: the record's own declared length. Stays 0xf8 regardless of `bufferSize`, so the event the
    /// WindowServer parses is identical to before we widened the buffer.
    static let lengthOffset = 0x04
    static let recordLength: UInt8 = 0xf8
    /// 0x08: the `CGSEventType`. We post a left-mouse-down then -up; the pair makes the window key. These
    /// match the public `CGEventType` values.
    static let eventTypeOffset = 0x08
    static let leftMouseDown: UInt8 = 0x01 // kCGEventLeftMouseDown
    static let leftMouseUp: UInt8 = 0x02 // kCGEventLeftMouseUp
    /// 0x20: `windowLocation`, the window-relative click point (a 16-byte CGPoint). We aim just outside the
    /// window's top-left corner: the mouse-down still makes it key, but the point hit-tests to no view, so
    /// nothing is clicked (avoids #5381's top-left hit in fullscreen, and any top-left chrome when windowed).
    /// Kept small: a wild value risks an app clamping it back to (0,0), i.e. onto real content.
    static let windowLocationOffset = 0x20
    static let offContentPoint = CGPoint(x: -1, y: -1)
    /// 0x3c: the target `CGWindowID`. The event is delivered to this window by id, not by the coordinate.
    static let windowIdOffset = 0x3c
    /// 0x3a: purpose undocumented. yabai and Hammerspoon set it to 0x10.
    static let unknownFlagOffset = 0x3a
    static let unknownFlagValue: UInt8 = 0x10
}

/// Makes the window `wid` the key window of its app by posting a synthetic left-click (down then up) to
/// the WindowServer. No public API moves key focus across apps. Ported from
/// https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468 (yabai's
/// `window_manager_make_key_window`). The click is aimed just outside the window (see `offContentPoint`)
/// so it makes the window key without actually clicking any of its content.
func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
    var wid = wid
    var point = MakeKeyWindowEvent.offContentPoint
    var bytes = [UInt8](repeating: 0, count: MakeKeyWindowEvent.bufferSize)
    bytes[MakeKeyWindowEvent.lengthOffset] = MakeKeyWindowEvent.recordLength
    bytes[MakeKeyWindowEvent.unknownFlagOffset] = MakeKeyWindowEvent.unknownFlagValue
    // deliver the event to this specific window by id (not by the click point below)
    memcpy(&bytes[MakeKeyWindowEvent.windowIdOffset], &wid, MemoryLayout<CGWindowID>.size)
    // window-relative click point just outside the frame: makes the window key, but hit-tests to no view
    memcpy(&bytes[MakeKeyWindowEvent.windowLocationOffset], &point, MemoryLayout<CGPoint>.size)
    // post a left-mouse-down then -up; the app reads the pair as "you are now key"
    bytes[MakeKeyWindowEvent.eventTypeOffset] = MakeKeyWindowEvent.leftMouseDown
    SLPSPostEventRecordTo(&psn, &bytes)
    bytes[MakeKeyWindowEvent.eventTypeOffset] = MakeKeyWindowEvent.leftMouseUp
    SLPSPostEventRecordTo(&psn, &bytes)
}

// MARK: - WindowServer notification tap (see WindowServerEvents.swift)
//
// SkyLight's notify-proc stream lets us learn about window lifecycle / geometry / Space changes straight
// from the WindowServer, immune to a busy or AX-lying app. Reverse-engineered + verified on macOS 26.5, and
// cross-checked against yabai (which uses the same `SLSRequestNotificationsForWindows` mechanism and the same
// event ids 804/1325/1326). The one switch that gates delivery is the per-window opt-in
// (`SLSRequestNotificationsForWindows`) — register notify procs + opt windows in, and the WindowServer
// pushes events. SkyLight calls the proc on whichever thread snarfs the datagram (the `_NSEventThread`); we
// keep that callback trivial and hop to main ourselves (see WindowServerEvents.notifyProc).
//
// Do NOT call `SLSConnectionDispatchNotificationsToMainQueueIfNotMainThread` on the AppKit-shared main
// connection: it is NOT needed for delivery (the opt-in alone delivers, confirmed at runtime), and on the
// shared connection it displaced AppKit's own coordinated-notification routing, so AppKit's
// `activeSpaceChanged:` / appearance handlers fired off-main on the `_NSEventThread` and crashed. It is kept
// declared below only to document the trap. All symbols exist since ≥10.10 (CoreGraphics re-exports the
// CGS-named aliases).

/// The per-connection notification callback: (event id, payload, payload length, context, connection id).
typealias CGSConnectionNotifyProc = @convention(c) (_ event: UInt32, _ data: UnsafeMutableRawPointer?, _ dataLength: Int, _ context: UnsafeMutableRawPointer?, _ cid: CGSConnectionID) -> Void

/// register `proc` to be called when `event` fires on `cid`. macOS 10.10+
@_silgen_name("SLSRegisterConnectionNotifyProc") @discardableResult
func SLSRegisterConnectionNotifyProc(_ cid: CGSConnectionID, _ proc: CGSConnectionNotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError

/// route this connection's notifications to the main dispatch queue. NOT needed for delivery, and harmful on
/// the AppKit-shared connection (see the MARK comment above) — declared only to document why we don't call it.
@_silgen_name("SLSConnectionDispatchNotificationsToMainQueueIfNotMainThread") @discardableResult
func SLSConnectionDispatchNotificationsToMainQueueIfNotMainThread(_ cid: CGSConnectionID) -> CGError

/// opt this connection into per-window notifications for the given windows (yabai's mechanism). macOS 10.10+
@_silgen_name("SLSRequestNotificationsForWindows") @discardableResult
func SLSRequestNotificationsForWindows(_ cid: CGSConnectionID, _ windowList: UnsafeMutablePointer<CGWindowID>, _ windowCount: Int32) -> CGError

/// fill `list` with the on-screen (current-Space) window ids, top-most first. `owner` 0 = all. macOS 10.10+
@_silgen_name("SLSGetOnScreenWindowList") @discardableResult
func SLSGetOnScreenWindowList(_ cid: CGSConnectionID, _ owner: CGSConnectionID, _ count: Int32, _ list: UnsafeMutablePointer<CGWindowID>, _ outCount: UnsafeMutablePointer<Int32>) -> CGError

// MARK: - WindowServer window query (batched snapshot — see windowserver/WindowServerQuery.swift)
//
// `SLSWindowQueryWindows` is ONE IPC returning a snapshot of the requested windows; the iterator getters
// then read that local snapshot (no per-field IPC). `Advance` returns Bool (true = positioned on a window).
// All since ≥10.10. These back the WindowServer-native model in `windowserver/`.

@_silgen_name("SLSWindowQueryWindows")
func SLSWindowQueryWindows(_ cid: CGSConnectionID, _ windows: CFArray, _ count: Int32) -> Unmanaged<CFTypeRef>

@_silgen_name("SLSWindowQueryResultCopyWindows")
func SLSWindowQueryResultCopyWindows(_ query: CFTypeRef) -> Unmanaged<CFTypeRef>

@_silgen_name("SLSWindowIteratorAdvance")
func SLSWindowIteratorAdvance(_ iterator: CFTypeRef) -> Bool

@_silgen_name("SLSWindowIteratorGetWindowID")
func SLSWindowIteratorGetWindowID(_ iterator: CFTypeRef) -> CGWindowID

@_silgen_name("SLSWindowIteratorGetPID")
func SLSWindowIteratorGetPID(_ iterator: CFTypeRef) -> pid_t

@_silgen_name("SLSWindowIteratorGetAttributes")
func SLSWindowIteratorGetAttributes(_ iterator: CFTypeRef) -> UInt64

@_silgen_name("SLSWindowIteratorGetLevel")
func SLSWindowIteratorGetLevel(_ iterator: CFTypeRef) -> Int32

@_silgen_name("SLSWindowIteratorGetSpaceTypeMask")
func SLSWindowIteratorGetSpaceTypeMask(_ iterator: CFTypeRef) -> UInt64

// returns the window frame in top-left-origin global coordinates — same system as kAXPosition/kAXSize and
// kCGWindowBounds (verified equal to both on macOS 26).
//
// This is the ONE private function we call that returns a struct BY VALUE. `@_silgen_name` binds a symbol
// using Swift's calling convention, which matches C only for register-returned results. A 32-byte CGRect is
// returned in SIMD registers on arm64 (so `@_silgen_name` looked correct, and does work there) but via a
// hidden sret pointer on the x86_64 SysV ABI. Under the Swift-convention binding that sret setup is wrong on
// x86_64: the iterator pointer lands in the wrong register, so the very next `SLSWindowIteratorAdvance`
// dereferences garbage and crashes inside SkyLight — on Intel Macs ONLY (issue #5819; arm64 never saw it).
// Bind it through a `@convention(c)` pointer instead so the correct C ABI (sret on x86_64, registers on arm64)
// is used on both. Every other private call we make returns a pointer or scalar, so this is the only one hit.
private let _SLSWindowIteratorGetBounds = unsafeBitCast(
    dlsym(dlopen(nil, RTLD_LAZY), "SLSWindowIteratorGetBounds")!,
    to: (@convention(c) (UnsafeRawPointer) -> CGRect).self)
func SLSWindowIteratorGetBounds(_ iterator: CFTypeRef) -> CGRect {
    _SLSWindowIteratorGetBounds(Unmanaged.passUnretained(iterator).toOpaque())
}

@_silgen_name("SLSWindowIteratorCopyTitle")
func SLSWindowIteratorCopyTitle(_ iterator: CFTypeRef) -> Unmanaged<CFString>?
