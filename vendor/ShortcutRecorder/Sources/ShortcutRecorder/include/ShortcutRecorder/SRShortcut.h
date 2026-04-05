//
//  Copyright 2018 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>
#import <ShortcutRecorder/SRKeyCodeTransformer.h>


NS_ASSUME_NONNULL_BEGIN

/*!
 @enum SRShortcutKey

 @discussion Keys of the dictionary that represents shortcut.
 */
typedef NSString *SRShortcutKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(ShortcutKey);

/*!
 @seealso SRShortcut/code
 */
extern SRShortcutKey const SRShortcutKeyKeyCode;

/*!
 @seealso SRShortcut/modifierFlags
 */
extern SRShortcutKey const SRShortcutKeyModifierFlags;

/*!
 @seealso SRShortcut/characters
 */
extern SRShortcutKey const SRShortcutKeyCharacters;

/*!
 @seealso SRShortcut/charactersIgnoringModifiers
 */
extern SRShortcutKey const SRShortcutKeyCharactersIgnoringModifiers;

extern NSString *const SRShortcutKeyCode __attribute__((deprecated("Deprecated in 3.0", "SRShortcutKeyKeyCode")));
extern NSString *const SRShortcutModifierFlagsKey __attribute__((deprecated("Deprecated in 3.0", "SRShortcutKeyModifierFlags")));
extern NSString *const SRShortcutCharacters __attribute__((deprecated("Deprecated in 3.0", "SRShortcutKeyCharacters")));
extern NSString *const SRShortcutCharactersIgnoringModifiers __attribute__((deprecated("", "SRShortcutKeyCharactersIgnoringModifiers")));

/*!
 Combination of a key code, modifier flags and optionally their characters
 representation at the time of recording.

 @note KVC access is compatible with ShortcutRecorder 2

 @note Two shortcuts are considered equal if their code and modifier flags match.
 */
NS_SWIFT_NAME(Shortcut)
@interface SRShortcut : NSObject <NSCopying, NSSecureCoding>

/*!
 @seealso SRShortcut/initWithCode:modifierFlags:characters:charactersIgnoringModifiers:
 */
+ (instancetype)shortcutWithCode:(SRKeyCode)aKeyCode
                   modifierFlags:(NSEventModifierFlags)aModifierFlags
                      characters:(nullable NSString *)aCharacters
     charactersIgnoringModifiers:(nullable NSString *)aCharactersIgnoringModifiers;

/*!
 Initialize the shortcut with a keyboard event.
 */
+ (nullable instancetype)shortcutWithEvent:(NSEvent *)aKeyboardEvent;

/*!
 Initialize the shortcut with a dictionary.

 @note Compatible with Shortcut Recorder 2 shortcuts.

 @seealso SRShortcutKey
 */
+ (nullable instancetype)shortcutWithDictionary:(NSDictionary *)aDictionary;

/*!
 Initialize the shortcut from a left-to-right ASCII key code and symbolic modifier flags e.g. @"⇧⌘A".
 */
+ (nullable instancetype)shortcutWithKeyEquivalent:(NSString *)aKeyEquivalent;

/*!
 Initialize the shortcut from a Cocoa Text system key binding.

 @seealso https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html
 */
+ (nullable instancetype)shortcutWithKeyBinding:(NSString *)aKeyBinding;

+ (instancetype)new NS_UNAVAILABLE;

/*!
 Designated initializer.

 @param aKeyCode A key code such as 0 ('a').

 @param aModifierFlags Modifier flags such as NSEventModifierFlagCommand.

 @param aCharacters Representation of the key code with modifier flags.

 @param aCharactersIgnoringModifiers Representation of the key code without modifier flags.

 @discussion
 If aCharacters is nil, an attempt is made to translate the given key code and modifier flags
 using SRASCIISymbolicKeyCodeTransformer. Similarly for aCharactersIgnoringModifiers.
 */
- (instancetype)initWithCode:(SRKeyCode)aKeyCode
               modifierFlags:(NSEventModifierFlags)aModifierFlags
                  characters:(nullable NSString *)aCharacters
 charactersIgnoringModifiers:(nullable NSString *)aCharactersIgnoringModifiers NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/*!
 A key code such as 0 ('a').
 */
@property (readonly) SRKeyCode keyCode;

/*!
 Modifier flags such as NSEventModifierFlagCommand | NSEventModifierFlagOption.
 */
@property (readonly) NSEventModifierFlags modifierFlags;

/*!
 Representation of the key code with modifier flags.

 @discussion
 Depends on system's locale and the active input source at the time when shortcut was taken.
 Does not participate in the equality test.
 */
@property (nullable, readonly) NSString *characters;

/*!
 Representation of the key code without modifier flags.

 @discussion
 Depends on system's locale and the active input source at the time when shortcut was taken.
 Does not participate in the equality test.
 */
@property (nullable, readonly) NSString *charactersIgnoringModifiers;

/*!
 Dictionary representation of the shortcut. Compatible with ShortcutRecorer 2

 @seealso SRShortcutKey
 */
@property (readonly) NSDictionary<SRShortcutKey, id> *dictionaryRepresentation;

/*!
 Return readable representation of the shortcut for user dialogs or accessibility.

 @param isASCII Same key code can refer to different characters depending on the input source.
                If isASCII is NO then the active input source is used. If it's YES ASCII input source is used.
                Pass YES for consistent results.
 */
- (NSString *)readableStringRepresentation:(BOOL)isASCII NS_SWIFT_NAME(readableStringRepresentation(isASCII:));

/*!
 Compare the shortcut to another shortcut.

 @discussion Override to compare properties of the receiver against another shortcut only.
 */
- (BOOL)isEqualToShortcut:(SRShortcut *)aShortcut;

/*!
 Compare the shortcut to a dictionary representation.

 @seealso dictionaryRepresentation
 */
- (BOOL)isEqualToDictionary:(NSDictionary<SRShortcutKey, id> *)aDictionary NS_SWIFT_NAME(isEqual(dictionary:));

/*!
 Compare the shortcut to Cocoa's key equivalent and modifier flags using the current input source.
 */
- (BOOL)isEqualToKeyEquivalent:(nullable NSString *)aKeyEquivalent
             withModifierFlags:(NSEventModifierFlags)aModifierFlags NS_SWIFT_NAME(isEqual(keyEquivalent:modifierFlags:));

/*!
 Compare the shortcut to Cocoa's key equivalent and modifier flags using the given key code transformer.
 */
- (BOOL)isEqualToKeyEquivalent:(NSString *)aKeyEquivalent
             withModifierFlags:(NSEventModifierFlags)aModifierFlags
              usingTransformer:(SRKeyCodeTransformer *)aTransformer NS_SWIFT_NAME(isEqual(keyEquivalent:modifierFlags:transformer:));


/*!
 Dictionary-like access to properties.

 @seealso SRShortcutKey
 */
- (nullable id)objectForKeyedSubscript:(SRShortcutKey)aKey;

@end


/*!
 Carbon versions of key code and modifier flags.
 */
@interface SRShortcut (Carbon)

@property (readonly) UInt32 carbonKeyCode;

@property (readonly) UInt32 carbonModifierFlags;

@end


/*!
 Check whether dictionary representations of shortcuts are equal (ShortcutRecorder 2).
 */
NS_INLINE BOOL SRShortcutEqualToShortcut(NSDictionary *a, NSDictionary *b) __attribute__((deprecated("Deprecated in 3.0", "SRShortcut/isEqual:")));
NS_INLINE BOOL SRShortcutEqualToShortcut(NSDictionary *a, NSDictionary *b)
{
    if (a == b)
        return YES;
    else if (a && !b)
        return NO;
    else if (!a && b)
        return NO;
    else
        return ([a[SRShortcutKeyKeyCode] isEqual:b[SRShortcutKeyKeyCode]] && [a[SRShortcutKeyModifierFlags] isEqual:b[SRShortcutKeyModifierFlags]]);
}

/*!
 Create ShortcutRecorder 2 shortcut.
 */
NS_INLINE NSDictionary *SRShortcutWithCocoaModifierFlagsAndKeyCode(NSEventModifierFlags aModifierFlags, SRKeyCode aKeyCode) __attribute__((deprecated("Deprecated in 3.0", "SRShortcut")));
NS_INLINE NSDictionary *SRShortcutWithCocoaModifierFlagsAndKeyCode(NSEventModifierFlags aModifierFlags, SRKeyCode aKeyCode)
{
    return @{SRShortcutKeyKeyCode: @(aKeyCode), SRShortcutKeyModifierFlags: @(aModifierFlags)};
}


/*!
 Return string representation of a shortcut with modifier flags replaced with their
 localized readable equivalents (e.g. ⌥ -> Option).
 */
NSString * _Nonnull SRReadableStringForCocoaModifierFlagsAndKeyCode(NSEventModifierFlags aModifierFlags, SRKeyCode aKeyCode) __attribute__((deprecated("Deprecated in 3.0", "SRShortcut/readableStringRepresentation:")));


/*!
 Return string representation of a shortcut with modifier flags replaced with their
 localized readable equivalents (e.g. ⌥ -> Option) and ASCII character with a key code.
 */
NSString * _Nonnull SRReadableASCIIStringForCocoaModifierFlagsAndKeyCode(NSEventModifierFlags aModifierFlags, SRKeyCode aKeyCode) __attribute__((deprecated("Deprecated in 3.0", "SRShortcut/readableStringRepresentation:")));


/*!
 Check whether a given key code with modifier flags is equal to a key equivalent and key equivalent modifier flags
 (e.g. from NSButton or NSMenuItem).

 @discussion
 On macOS some key combinations can have "alternates". E.g. option-A can be represented both as "option-A" and "å".
 */
BOOL SRKeyCodeWithFlagsEqualToKeyEquivalentWithFlags(SRKeyCode aKeyCode,
                                                     NSEventModifierFlags aKeyCodeFlags,
                                                     NSString * _Nullable aKeyEquivalent,
                                                     NSEventModifierFlags aKeyEquivalentModifierFlags) __attribute__((deprecated("Deprecated in 3.0", "SRShortcut/isEqualToKeyEquivalent:withModifierFlags:")));

NS_ASSUME_NONNULL_END
