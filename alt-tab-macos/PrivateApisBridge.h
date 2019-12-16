// In this .h file, we define symbols of private APIs so we can use these APIs in the project
// see Webkit repo: https://github.com/WebKit/webkit/blob/master/Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h
// see Hammerspoon issue: https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
// see Alt-tab-macos issue: https://github.com/lwouis/alt-tab-macos/pull/87#issuecomment-558624755

#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>

typedef uint32_t CGSConnectionID;
typedef uint32_t CGSWindowID;
typedef uint32_t CGSWindowCount;
typedef uint32_t CGSWindowCaptureOptions;
enum {
    kCGSWindowCaptureNominalResolution = 0x0200,
    kCGSCaptureIgnoreGlobalClipShape = 0x0800,
};

extern CGSConnectionID CGSMainConnectionID(void);

// returns an array of CGImage of the windows which ID is given as `windowList`. `windowList` is supposed to be an array of IDs but in my test on High Sierra, the function ignores other IDs than the first, and always returns the screenshot of the first window in the array
// * performance: the `HW` in the name seems to imply better performance, and it was observed by some contributors that it seems to be faster (see https://github.com/lwouis/alt-tab-macos/issues/45) than other methods
// * minimized windows: the function can return screenshots of minimized windows
// * windows in other spaces: ?
extern CFArrayRef CGSHWCaptureWindowList(CGSConnectionID connectionId, CGSWindowID *windowList, CGSWindowCount windowCount, CGSWindowCaptureOptions options);

// returns the CGImage of the window which ID is given in `wid`
// * performance: it seems that this function performs similarly to public API `CGWindowListCreateImage`
// * minimized windows: the function can return screenshots of minimized windows
// * windows in other spaces: ?
extern CGError CGSCaptureWindowsContentsToRectWithOptions(CGSConnectionID connectionId, CGSWindowID *windowId, bool windowOnly, CGRect rect, CGSWindowCaptureOptions options, CGImageRef *image);

// returns the size of a window
// * performance: it seems that this function is faster than the public API AX calls to get a window bounds
// * minimized windows: ?
// * windows in other spaces: ?
extern CGError SLSGetWindowBounds(CGSConnectionID connectionId, CGSWindowID *windowId, CGRect *frame);

typedef uint32_t SLPSMode;
enum {
    kCPSAllWindows = 0x100,
    kCPSUserGenerated = 0x200,
    kCPSNoWindows = 0x400,
};

// focuses a window
// * performance: faster than AXUIElementPerformAction(kAXRaiseAction)
// * minimized windows: yes
// * windows in other spaces: ?
extern CGError _SLPSSetFrontProcessWithOptions(ProcessSerialNumber *psn, CGSWindowID windowId, SLPSMode mode);

extern CGError SLSGetWindowOwner(CGSConnectionID connectionId, CGSWindowID windowId, CGSConnectionID *windowConnectionId);

extern CGError SLSGetConnectionPSN(CGSConnectionID connectionId, ProcessSerialNumber *psn);

extern CGError SLPSPostEventRecordTo(ProcessSerialNumber *psn, uint8_t *bytes);

// The following function was taken from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
static void window_manager_make_key_window(ProcessSerialNumber *psn, uint32_t windowId) {
    // the information specified in the events below consists of the "special" category, event type, and modifiers,
    // basically synthesizing a mouse-down and up event targetted at a specific window of the application,
    // but it doesn't actually get treated as a mouse-click normally would.
    uint8_t bytes1[0xf8] = {
            [0x04] = 0xF8,
            [0x08] = 0x01,
            [0x3a] = 0x10
    };
    uint8_t bytes2[0xf8] = {
            [0x04] = 0xF8,
            [0x08] = 0x02,
            [0x3a] = 0x10
    };
    memcpy(bytes1 + 0x3c, &windowId, sizeof(uint32_t));
    memset(bytes1 + 0x20, 0xFF, 0x10);
    memcpy(bytes2 + 0x3c, &windowId, sizeof(uint32_t));
    memset(bytes2 + 0x20, 0xFF, 0x10);
    SLPSPostEventRecordTo(psn, bytes1);
    SLPSPostEventRecordTo(psn, bytes2);
}

// returns the window ID of the provided AXUIElement
extern AXError _AXUIElementGetWindow(AXUIElementRef axUiElement, uint32_t *windowId);
