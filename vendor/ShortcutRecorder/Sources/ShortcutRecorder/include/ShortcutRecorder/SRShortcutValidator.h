//
//  Copyright 2006 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>

#import <ShortcutRecorder/SRRecorderControl.h>


NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(ShortcutValidatorDelegate)
@protocol SRShortcutValidatorDelegate;

/*!
 Validate shortcut by checking whether it is taken by other parts of the application and system.
 */
NS_SWIFT_NAME(ShortcutValidator)
@interface SRShortcutValidator : NSObject <SRRecorderControlDelegate>

@property (nullable, weak) NSObject<SRShortcutValidatorDelegate> *delegate;

- (instancetype)initWithDelegate:(nullable NSObject<SRShortcutValidatorDelegate> *)aDelegate NS_DESIGNATED_INITIALIZER;

/*!
 Check whether shortcut is valid.

 @return YES if shortcut is valid.

 @discussion
 Key is checked in the following order:
     1. Delegate's shortcutValidator:isShortcutValid:reason:
     2. If delegate allows, system-wide shortcuts are checked
     3. If delegate allows, application menu it checked

 @seealso SRShortcutValidatorDelegate
 */
- (BOOL)validateShortcut:(SRShortcut *)aShortcut error:(NSError * _Nullable *)outError NS_SWIFT_NAME(validate(shortcut:));

/*!
 Check whether delegate allows the shortcut.

 @return YES if shortcut is valid.

 @discussion Defaults to YES if delegate does not implement the method.
 */
- (BOOL)validateShortcutAgainstDelegate:(SRShortcut *)aShortcut error:(NSError * _Nullable *)outError NS_SWIFT_NAME(validateAgainstDelegate(shortcut:));

/*!
 Check whether shortcut is taken by system-wide shortcuts.

 @return YES if shortcut is valid.

 @seealso SRShortcutValidatorDelegate/shortcutValidatorShouldCheckSystemShortcuts:
 */
- (BOOL)validateShortcutAgainstSystemShortcuts:(SRShortcut *)aShortcut error:(NSError * _Nullable *)outError NS_SWIFT_NAME(validateAgainstSystemShortcuts(shortcut:));

/*!
 Check whether shortcut is taken by a menu item.

 @return YES if shortcut is valid.

 @seealso SRShortcutValidatorDelegate/shortcutValidatorShouldCheckMenu:
 */
- (BOOL)validateShortcut:(SRShortcut *)aShortcut againstMenu:(NSMenu *)aMenu error:(NSError * _Nullable *)outError NS_SWIFT_NAME(validate(shortcut:againstMenu:));

@end


@interface SRShortcutValidator(Deprecated)

- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlagsTaken:(NSEventModifierFlags)aFlags error:(NSError * _Nullable *)outError __attribute__((deprecated("", "validateShortcut:error:"))) NS_SWIFT_UNAVAILABLE("validateShortcut(_:)");
- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlagTakenInDelegate:(NSEventModifierFlags)aFlags error:(NSError * _Nullable *)outError __attribute__((deprecated("", "validateShortcutAgainstDelegate:error:"))) NS_SWIFT_UNAVAILABLE("validateShortcutAgainstDelegate(_:)");
- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlagsTakenInSystemShortcuts:(NSEventModifierFlags)aFlags error:(NSError * _Nullable *)outError __attribute__((deprecated("", "validateShortcutAgainstSystemShortcuts:error:"))) NS_SWIFT_UNAVAILABLE("Use validateShortcutAgainstSystemShortcuts(_:)");
- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlags:(NSEventModifierFlags)aFlags takenInMenu:(NSMenu *)aMenu error:(NSError * _Nullable *)outError __attribute__((deprecated("", "validateShortcut:againstMenu:error:"))) NS_SWIFT_UNAVAILABLE("Use validateShortcut(_:againstMenu:)");

@end


@protocol SRShortcutValidatorDelegate

@optional

/*!
 Ask the delegate if the shortcut is valid.

 @param aValidator The validator that is validating the shortcut.

 @param aShortcut The shortcut to validate.

 @param outReason If the delegate decides that the shortcut is invalid, it may pass out an error message.

 @return YES if shortcut is valid; otherwise, NO.
 */
- (BOOL)shortcutValidator:(SRShortcutValidator *)aValidator isShortcutValid:(SRShortcut *)aShortcut reason:(NSString * _Nullable * _Nonnull)outReason;

/*!
    Same as -shortcutValidator:isShortcutValid:reason: but return value is flipped. I.e. YES means shortcut is invalid.
 */
- (BOOL)shortcutValidator:(SRShortcutValidator *)aValidator isKeyCode:(SRKeyCode)aKeyCode andFlagsTaken:(NSEventModifierFlags)aFlags reason:(NSString * _Nullable * _Nonnull)outReason __attribute__((deprecated("", "shortcutValidator:isShortcutValid:reason:")));

/*!
 Ask the delegate whether validator should check key equivalents of app's menu items.

 @param aValidator The validator that is validating the shortcut.

 @return YES if the validator should check key equivalents of app's menu items; otherwise, NO.

 @discussion If it is not implemented, checking proceeds as if this method had returned YES.
 */
- (BOOL)shortcutValidatorShouldCheckMenu:(SRShortcutValidator *)aValidator;

/*!
 Ask the delegate whether it should check system shortcuts.

 @param aValidator The validator that is validating the shortcut.

 @return YES if the validator should check system shortcuts; otherwise, NO.

 @discussion If it is not implemented, checking proceeds as if this method had returned YES.
 */
- (BOOL)shortcutValidatorShouldCheckSystemShortcuts:(SRShortcutValidator *)aValidator;

/*!
 Ask the delegate whether it should use ASCII representation of a key code for error messages.

 @param aValidator The validator that is validating the shortcut.

 @return YES if the validator should use ASCII representation; otherwise, NO.

 @discussion If it is not implemented, ASCII representation of a key code is used.
 */
- (BOOL)shortcutValidatorShouldUseASCIIStringForKeyCodes:(SRShortcutValidator *)aValidator;

@end


@interface NSMenuItem (SRShortcutValidator)

/*!
    Full path to the menu item. E.g. "Window → Zoom"
 */
- (NSString *)SR_path;

@end

NS_ASSUME_NONNULL_END
