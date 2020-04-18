#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "ShortcutRecorder.h"
#import "SRCommon.h"
#import "SRKeyBindingTransformer.h"
#import "SRKeyCodeTransformer.h"
#import "SRKeyEquivalentModifierMaskTransformer.h"
#import "SRKeyEquivalentTransformer.h"
#import "SRModifierFlagsTransformer.h"
#import "SRRecorderControl.h"
#import "SRRecorderControlStyle.h"
#import "SRShortcut.h"
#import "SRShortcutAction.h"
#import "SRShortcutController.h"
#import "SRShortcutFormatter.h"
#import "SRShortcutValidator.h"

FOUNDATION_EXPORT double ShortcutRecorderVersionNumber;
FOUNDATION_EXPORT const unsigned char ShortcutRecorderVersionString[];

