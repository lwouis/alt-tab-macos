//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN

/*!
 Format shortcut into a string.

 @discussion
 Reverse formatting is supported for literal ASCII transformers with left-to-right layout.
 */
NS_SWIFT_NAME(ShortcutFormatter)
@interface SRShortcutFormatter : NSFormatter

@property IBInspectable BOOL isKeyCodeLiteral;
@property IBInspectable BOOL areModifierFlagsLiteral;
@property IBInspectable BOOL usesASCIICapableKeyboardInputSource;
@property IBInspectable NSUserInterfaceLayoutDirection layoutDirection;

@end

NS_ASSUME_NONNULL_END
