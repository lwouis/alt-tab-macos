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

/// returns an array of displays (as NSDictionary), each with its Spaces (as NSDictionary) under the "Spaces"
/// key, each Space carrying its id (as UInt64) under "id64".
/// /!\ only returns correct values when the user has checked System Settings > Desktop & Dock >
/// Mission Control > "Displays have separate Spaces". Unchecked, every display collapses into one entry whose
/// "Display Identifier" is the literal string "Main", so per-screen topology is unavailable.
/// * macOS 10.10+
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

/// Only the bits we pass. The rest of the map was surveyed and is not production code.
struct CGSCopyWindowsOptions: OptionSet {
    let rawValue: Int
    static let invisible1 = CGSCopyWindowsOptions(rawValue: 1 << 0)
    // retrieves windows when their app is assigned to All Spaces, and windows at ScreenSaver level 1000
    static let screenSaverLevel1000 = CGSCopyWindowsOptions(rawValue: 1 << 1)
    static let invisible2 = CGSCopyWindowsOptions(rawValue: 1 << 2)
}

/// We pass an empty set for both the set- and clear-tags arguments, so none of the tag bits are named here.
struct CGSCopyWindowsTags: OptionSet {
    let rawValue: Int
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
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: CGSSpaceMask.RawValue, _ wids: CFArray) -> CFArray?

/// returns window level (see definition in CGWindowLevel.h) of provided window
/// * macOS 10.10+
@_silgen_name("CGSGetWindowLevel") @discardableResult
func CGSGetWindowLevel(_ cid: CGSConnectionID, _ wid: CGWindowID, _ level: UnsafeMutablePointer<CGWindowLevel>) -> CGError

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

/// Makes the window key without aiming at its content. Both coordinate fields must stay outside
/// content (#5381, #5900), and the down must have a matching up so clients such as SDL do not keep
/// a pending focus click that suppresses mouse confinement. See WindowFocusEventSpecs.md.
func makeKeyWindow(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID) {
    WindowFocusEvent.post(windowId: wid) { bytes in
        SLPSPostEventRecordTo(&psn, bytes)
    }
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
// Do NOT call `SLSConnectionDispatchNotificationsToMainQueueIfNotMainThread` on this connection: it is not
// needed for delivery, and it displaces AppKit's own coordinated-notification routing on the connection they
// share, which fires AppKit's `activeSpaceChanged:` / appearance handlers off-main and crashes. Delivery was
// confirmed at runtime to need only the per-window opt-in below, never that call. All symbols below exist
// since ≥10.10 (CoreGraphics re-exports the CGS-named aliases).

/// The per-connection notification callback: (event id, payload, payload length, context, connection id).
typealias CGSConnectionNotifyProc = @convention(c) (_ event: UInt32, _ data: UnsafeMutableRawPointer?, _ dataLength: Int, _ context: UnsafeMutableRawPointer?, _ cid: CGSConnectionID) -> Void

/// register `proc` to be called when `event` fires on `cid`. macOS 10.10+
@_silgen_name("SLSRegisterConnectionNotifyProc") @discardableResult
func SLSRegisterConnectionNotifyProc(_ cid: CGSConnectionID, _ proc: CGSConnectionNotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError

/// opt this connection into per-window notifications for the given windows (yabai's mechanism). macOS 10.10+.
/// REPLACES this connection's watch list — it does not add to it. Always pass every wid you still want to
/// hear from; passing only the new ones silences all the others (measured on macOS 26.5: a live run that sent
/// deltas saw 0 order-outs, 0 destroys and 0 focus events instead of 91 / 143 / 51, while the
/// connection-wide creates and moves kept arriving, so nothing looked broken until windows stopped being
/// removed). There is also no explicit way back: SkyLight exports no `SLSRemoveNotificationsForWindows` /
/// `SLSStopNotificationsForWindows` (dlsym'd on macOS 26), so dropping a wid from the next call is the only
/// unsubscribe there is.
@_silgen_name("SLSRequestNotificationsForWindows") @discardableResult
func SLSRequestNotificationsForWindows(_ cid: CGSConnectionID, _ windowList: UnsafeMutablePointer<CGWindowID>, _ windowCount: Int32) -> CGError

// MARK: - WindowServer window query (batched snapshot — see windowserver/WindowServerQuery.swift)
//
// `SLSWindowQueryWindows` is ONE IPC returning a snapshot of the requested windows; the iterator getters
// then read that local snapshot (no per-field IPC). `Advance` returns Bool (true = positioned on a window).
// All since ≥10.10. These back the WindowServer-native model in `windowserver/`.

/// The last argument is a set of options, not the window count. Bit 0 asks for titles: without it
/// `SLSWindowIteratorCopyTitle` answers nil for every row, and a window whose app gives accessibility an
/// empty title (Chrome web apps) falls back to its app name (#6089). Measured on macOS 15.7 and 27.0.1:
/// every other field, and the rows returned, are the same whatever is passed.
@_silgen_name("SLSWindowQueryWindows")
func SLSWindowQueryWindows(_ cid: CGSConnectionID, _ windows: CFArray, _ options: Int32) -> Unmanaged<CFTypeRef>

enum SLSWindowQueryOptions {
    static let titles: Int32 = 1 << 0
}

@_silgen_name("SLSWindowQueryResultCopyWindows")
func SLSWindowQueryResultCopyWindows(_ query: CFTypeRef) -> Unmanaged<CFTypeRef>

@_silgen_name("SLSWindowIteratorAdvance")
func SLSWindowIteratorAdvance(_ iterator: CFTypeRef) -> Bool

@_silgen_name("SLSWindowIteratorGetWindowID")
func SLSWindowIteratorGetWindowID(_ iterator: CFTypeRef) -> CGWindowID

@_silgen_name("SLSWindowIteratorGetParentID")
func SLSWindowIteratorGetParentID(_ iterator: CFTypeRef) -> CGWindowID

@_silgen_name("SLSWindowIteratorGetAlpha")
func SLSWindowIteratorGetAlpha(_ iterator: CFTypeRef) -> Float

@_silgen_name("SLSWindowIteratorGetPID")
func SLSWindowIteratorGetPID(_ iterator: CFTypeRef) -> pid_t

@_silgen_name("SLSWindowIteratorGetAttributes")
func SLSWindowIteratorGetAttributes(_ iterator: CFTypeRef) -> UInt64

@_silgen_name("SLSWindowIteratorGetLevel")
func SLSWindowIteratorGetLevel(_ iterator: CFTypeRef) -> Int32

@_silgen_name("SLSWindowIteratorGetSpaceTypeMask")
func SLSWindowIteratorGetSpaceTypeMask(_ iterator: CFTypeRef) -> UInt64

/// A SECOND bitfield alongside `GetAttributes`, and the one that carries minimized / app-hidden /
/// fullscreen. Decoded by `WsWindowState`; see `WsWindowStateSpecs.md` for the mapped bits and the state
/// matrix that proves each one specific.
@_silgen_name("SLSWindowIteratorGetTags")
func SLSWindowIteratorGetTags(_ iterator: CFTypeRef) -> UInt64

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
