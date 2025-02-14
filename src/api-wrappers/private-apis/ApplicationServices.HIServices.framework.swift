/// for some reason, this attribute is missing from ApplicationServices.HIServices.AXUIElement
/// returns the CGWindowID of the provided AXUIElement
/// * macOS 10.10+
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

/// returns an AXUIElement given a Data object. Data object should hold:
/// - pid (4 bytes)
/// - 0 (4 bytes)
/// - 0x636f636f (4 bytes)
/// - AXUIElementID (8 bytes)
@_silgen_name("_AXUIElementCreateWithRemoteToken") @discardableResult
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

/// for some reason, this constant is missing from ApplicationServices.HIServices.AXRoleConstants
let kAXDocumentWindowSubrole = "AXDocumentWindow"

/// for some reason, these constants are missing from ApplicationServices.HIServices.AXAttributeConstants
let kAXFullscreenAttribute = "AXFullScreen"
let kAXStatusLabelAttribute = "AXStatusLabel"

/// for some reason, these notifications are missing from ApplicationServices.HIServices.AXNotificationConstants
enum MissionControlState: String, CaseIterable {
    case showAllWindows = "AXExposeShowAllWindows"
    case showFrontWindows = "AXExposeShowFrontWindows"
    case showDesktop = "AXExposeShowDesktop"
    case inactive = "AXExposeExit"
}

/// this function from ApplicationServices.HIServices.Processes has been deprecated and removed, with no replacement
/// returns info about a given psn
/// * macOS 10.9-10.15 (officially removed in 10.9, but available as a private API still)
@_silgen_name("GetProcessInformation") @discardableResult
func GetProcessInformation(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ info: UnsafeMutablePointer<ProcessInfoRec>) -> OSErr

/// this function from ApplicationServices.HIServices.Processes has been deprecated and removed, with no replacement
/// returns the psn for a given pid
/// * macOS 10.9-10.15 (officially removed in 10.9, but available as a private API still)
@_silgen_name("GetProcessForPID") @discardableResult
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus


