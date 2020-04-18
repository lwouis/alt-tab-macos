//
//  Copyright 2006 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <stdint.h>


NS_ASSUME_NONNULL_BEGIN

/*!
 Mask representing subset of Cocoa modifier flags suitable for shortcuts.
 */
NS_SWIFT_NAME(CocoaModifierFlagsMask)
static const NSEventModifierFlags SRCocoaModifierFlagsMask = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagControl;


/*!
 Mask representing subset of Carbon modifier flags suitable for shortcuts.
 */
NS_SWIFT_NAME(CarbonModifierFlagsMask)
static const UInt32 SRCarbonModifierFlagsMask = cmdKey | optionKey | shiftKey | controlKey;


/*!
 Dawable unicode characters for key codes that do not have appropriate constants in Carbon and Cocoa.

 @seealso SRKeyCodeString
 */
typedef NS_ENUM(unichar, SRKeyCodeGlyph)
{
    SRKeyCodeGlyphTabRight = 0x21E5, // ⇥
    SRKeyCodeGlyphTabLeft = 0x21E4, // ⇤
    SRKeyCodeGlyphReturn = 0x2305, // ⌅
    SRKeyCodeGlyphReturnR2L = 0x21A9, // ↩
    SRKeyCodeGlyphDeleteLeft = 0x232B, // ⌫
    SRKeyCodeGlyphDeleteRight = 0x2326, // ⌦
    SRKeyCodeGlyphPadClear = 0x2327, // ⌧
    SRKeyCodeGlyphLeftArrow = 0x2190, // ←
    SRKeyCodeGlyphRightArrow = 0x2192, // →
    SRKeyCodeGlyphUpArrow = 0x2191, // ↑
    SRKeyCodeGlyphDownArrow = 0x2193, // ↓
    SRKeyCodeGlyphPageDown = 0x21DF, // ⇟
    SRKeyCodeGlyphPageUp = 0x21DE, // ⇞
    SRKeyCodeGlyphNorthwestArrow = 0x2196, // ↖
    SRKeyCodeGlyphSoutheastArrow = 0x2198, // ↘
    SRKeyCodeGlyphEscape = 0x238B, // ⎋
    SRKeyCodeGlyphSpace = 0x0020, // ' '
    SRKeyCodeGlyphJISUnderscore = 0xFF3F, // ＿
    SRKeyCodeGlyphJISComma = 0x3001, // 、
    SRKeyCodeGlyphJISYen = 0x00A5, // ¥
    SRKeyCodeGlyphANSI0 = 0x30, // 0
    SRKeyCodeGlyphANSI1 = 0x31, // 1
    SRKeyCodeGlyphANSI2 = 0x32, // 2
    SRKeyCodeGlyphANSI3 = 0x33, // 3
    SRKeyCodeGlyphANSI4 = 0x34, // 4
    SRKeyCodeGlyphANSI5 = 0x35, // 5
    SRKeyCodeGlyphANSI6 = 0x36, // 6
    SRKeyCodeGlyphANSI7 = 0x37, // 7
    SRKeyCodeGlyphANSI8 = 0x38, // 8
    SRKeyCodeGlyphANSI9 = 0x39, // 9
    SRKeyCodeGlyphANSIEqual = 0x3d, // =
    SRKeyCodeGlyphANSIMinus = 0x2d, // -
    SRKeyCodeGlyphANSISlash = 0x2f, // /
    SRKeyCodeGlyphANSIPeriod = 0x2e // .
} NS_SWIFT_NAME(KeyCodeGlyph);


/*!
 NSString version of SRKeyCodeGlyph

 @seealso SRKeyCodeGlyph
 */
typedef NSString *SRKeyCodeString NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(KeyCodeString);
extern SRKeyCodeString const SRKeyCodeStringTabRight;
extern SRKeyCodeString const SRKeyCodeStringTabLeft;
extern SRKeyCodeString const SRKeyCodeStringReturn;
extern SRKeyCodeString const SRKeyCodeStringReturnR2L;
extern SRKeyCodeString const SRKeyCodeStringDeleteLeft;
extern SRKeyCodeString const SRKeyCodeStringDeleteRight;
extern SRKeyCodeString const SRKeyCodeStringPadClear;
extern SRKeyCodeString const SRKeyCodeStringLeftArrow;
extern SRKeyCodeString const SRKeyCodeStringRightArrow;
extern SRKeyCodeString const SRKeyCodeStringUpArrow;
extern SRKeyCodeString const SRKeyCodeStringDownArrow;
extern SRKeyCodeString const SRKeyCodeStringPageDown;
extern SRKeyCodeString const SRKeyCodeStringPageUp;
extern SRKeyCodeString const SRKeyCodeStringNorthwestArrow;
extern SRKeyCodeString const SRKeyCodeStringSoutheastArrow;
extern SRKeyCodeString const SRKeyCodeStringEscape;
extern SRKeyCodeString const SRKeyCodeStringSpace;
extern SRKeyCodeString const SRKeyCodeStringHelp;
extern SRKeyCodeString const SRKeyCodeStringJISUnderscore;
extern SRKeyCodeString const SRKeyCodeStringJISComma;
extern SRKeyCodeString const SRKeyCodeStringJISYen;


/*!
 Dawable unicode characters for modifier flags.

 @seealso SRModifierFlagString
 */
typedef NS_ENUM(unichar, SRModifierFlagGlyph)
{
    SRModifierFlagGlyphCommand = kCommandUnicode, // ⌘
    SRModifierFlagGlyphOption = kOptionUnicode,  // ⌥
    SRModifierFlagGlyphShift = kShiftUnicode, // ⇧
    SRModifierFlagGlyphControl = kControlUnicode // ⌃
} NS_SWIFT_NAME(ModifierFlagGlyph);


/*!
 Known key codes.
 */
typedef NS_ENUM(uint16_t, SRKeyCode) {
    SRKeyCodeNone = UINT16_MAX,

    SRKeyCodeA NS_SWIFT_NAME(ansiA) = kVK_ANSI_A,
    SRKeyCodeS NS_SWIFT_NAME(ansiS) = kVK_ANSI_S,
    SRKeyCodeD NS_SWIFT_NAME(ansiD) = kVK_ANSI_D,
    SRKeyCodeF NS_SWIFT_NAME(ansiF) = kVK_ANSI_F,
    SRKeyCodeH NS_SWIFT_NAME(ansiH) = kVK_ANSI_H,
    SRKeyCodeG NS_SWIFT_NAME(ansiG) = kVK_ANSI_G,
    SRKeyCodeZ NS_SWIFT_NAME(ansiZ) = kVK_ANSI_Z,
    SRKeyCodeX NS_SWIFT_NAME(ansiX) = kVK_ANSI_X,
    SRKeyCodeC NS_SWIFT_NAME(ansiC) = kVK_ANSI_C,
    SRKeyCodeV NS_SWIFT_NAME(ansiV) = kVK_ANSI_V,
    SRKeyCodeB NS_SWIFT_NAME(ansiB) = kVK_ANSI_B,
    SRKeyCodeQ NS_SWIFT_NAME(ansiQ) = kVK_ANSI_Q,
    SRKeyCodeW NS_SWIFT_NAME(ansiW) = kVK_ANSI_W,
    SRKeyCodeE NS_SWIFT_NAME(ansiE) = kVK_ANSI_E,
    SRKeyCodeR NS_SWIFT_NAME(ansiR) = kVK_ANSI_R,
    SRKeyCodeY NS_SWIFT_NAME(ansiY) = kVK_ANSI_Y,
    SRKeyCodeT NS_SWIFT_NAME(ansiT) = kVK_ANSI_T,
    SRKeyCode1 NS_SWIFT_NAME(ansi1) = kVK_ANSI_1,
    SRKeyCode2 NS_SWIFT_NAME(ansi2) = kVK_ANSI_2,
    SRKeyCode3 NS_SWIFT_NAME(ansi3) = kVK_ANSI_3,
    SRKeyCode4 NS_SWIFT_NAME(ansi4) = kVK_ANSI_4,
    SRKeyCode6 NS_SWIFT_NAME(ansi6) = kVK_ANSI_6,
    SRKeyCode5 NS_SWIFT_NAME(ansi5) = kVK_ANSI_5,
    SRKeyCodeEqual NS_SWIFT_NAME(ansiEqual) = kVK_ANSI_Equal,
    SRKeyCode9 NS_SWIFT_NAME(ansi9) = kVK_ANSI_9,
    SRKeyCode7 NS_SWIFT_NAME(ansi7) = kVK_ANSI_7,
    SRKeyCodeMinus NS_SWIFT_NAME(ansiMinus) = kVK_ANSI_Minus,
    SRKeyCode8 NS_SWIFT_NAME(ansi8) = kVK_ANSI_8,
    SRKeyCode0 NS_SWIFT_NAME(ansi0) = kVK_ANSI_0,
    SRKeyCodeRightBracket NS_SWIFT_NAME(ansiRightBracket) = kVK_ANSI_RightBracket,
    SRKeyCodeO NS_SWIFT_NAME(ansiO) = kVK_ANSI_O,
    SRKeyCodeU NS_SWIFT_NAME(ansiU) = kVK_ANSI_U,
    SRKeyCodeLeftBracket NS_SWIFT_NAME(ansiLeftBracket) = kVK_ANSI_LeftBracket,
    SRKeyCodeI NS_SWIFT_NAME(ansiI) = kVK_ANSI_I,
    SRKeyCodeP NS_SWIFT_NAME(ansiP) = kVK_ANSI_P,
    SRKeyCodeL NS_SWIFT_NAME(ansiL) = kVK_ANSI_L,
    SRKeyCodeJ NS_SWIFT_NAME(ansiJ) = kVK_ANSI_J,
    SRKeyCodeQuote NS_SWIFT_NAME(ansiQuote) = kVK_ANSI_Quote,
    SRKeyCodeK NS_SWIFT_NAME(ansiK) = kVK_ANSI_K,
    SRKeyCodeSemicolon NS_SWIFT_NAME(ansiSemicolon) = kVK_ANSI_Semicolon,
    SRKeyCodeBackslash NS_SWIFT_NAME(ansiBackslash) = kVK_ANSI_Backslash,
    SRKeyCodeComma NS_SWIFT_NAME(ansiComma) = kVK_ANSI_Comma,
    SRKeyCodeSlash NS_SWIFT_NAME(ansiSlash) = kVK_ANSI_Slash,
    SRKeyCodeN NS_SWIFT_NAME(ansiN) = kVK_ANSI_N,
    SRKeyCodeM NS_SWIFT_NAME(ansiM) = kVK_ANSI_M,
    SRKeyCodePeriod NS_SWIFT_NAME(ansiPeriod) = kVK_ANSI_Period,
    SRKeyCodeGrave NS_SWIFT_NAME(ansiGrave) = kVK_ANSI_Grave,
    SRKeyCodeKeypadDecimal NS_SWIFT_NAME(ansiKeypadDecimal) = kVK_ANSI_KeypadDecimal,
    SRKeyCodeKeypadMultiply NS_SWIFT_NAME(ansiKeypadMultiply) = kVK_ANSI_KeypadMultiply,
    SRKeyCodeKeypadPlus NS_SWIFT_NAME(ansiKeypadPlus) = kVK_ANSI_KeypadPlus,
    SRKeyCodeKeypadClear NS_SWIFT_NAME(ansiKeypadClear) = kVK_ANSI_KeypadClear,
    SRKeyCodeKeypadDivide NS_SWIFT_NAME(ansiKeypadDivide) = kVK_ANSI_KeypadDivide,
    SRKeyCodeKeypadEnter NS_SWIFT_NAME(ansiKeypadEnter) = kVK_ANSI_KeypadEnter,
    SRKeyCodeKeypadMinus NS_SWIFT_NAME(ansiKeypadMinus) = kVK_ANSI_KeypadMinus,
    SRKeyCodeKeypadEquals NS_SWIFT_NAME(ansiKeypadEquals) = kVK_ANSI_KeypadEquals,
    SRKeyCodeKeypad0 NS_SWIFT_NAME(ansiKeypad0) = kVK_ANSI_Keypad0,
    SRKeyCodeKeypad1 NS_SWIFT_NAME(ansiKeypad1) = kVK_ANSI_Keypad1,
    SRKeyCodeKeypad2 NS_SWIFT_NAME(ansiKeypad2) = kVK_ANSI_Keypad2,
    SRKeyCodeKeypad3 NS_SWIFT_NAME(ansiKeypad3) = kVK_ANSI_Keypad3,
    SRKeyCodeKeypad4 NS_SWIFT_NAME(ansiKeypad4) = kVK_ANSI_Keypad4,
    SRKeyCodeKeypad5 NS_SWIFT_NAME(ansiKeypad5) = kVK_ANSI_Keypad5,
    SRKeyCodeKeypad6 NS_SWIFT_NAME(ansiKeypad6) = kVK_ANSI_Keypad6,
    SRKeyCodeKeypad7 NS_SWIFT_NAME(ansiKeypad7) = kVK_ANSI_Keypad7,
    SRKeyCodeKeypad8 NS_SWIFT_NAME(ansiKeypad8) = kVK_ANSI_Keypad8,
    SRKeyCodeKeypad9 NS_SWIFT_NAME(ansiKeypad9) = kVK_ANSI_Keypad9,

    SRKeyCodeReturn NS_SWIFT_NAME(return) = kVK_Return,
    SRKeyCodeTab NS_SWIFT_NAME(tab) = kVK_Tab,
    SRKeyCodeSpace NS_SWIFT_NAME(space) = kVK_Space,
    SRKeyCodeDelete NS_SWIFT_NAME(delete) = kVK_Delete,
    SRKeyCodeEscape NS_SWIFT_NAME(escape) = kVK_Escape,
    SRKeyCodeCapsLock NS_SWIFT_NAME(capslock) = kVK_CapsLock,
    SRKeyCodeF17 NS_SWIFT_NAME(f17) = kVK_F17,
    SRKeyCodeVolumeUp NS_SWIFT_NAME(volumeUp) = kVK_VolumeUp,
    SRKeyCodeVolumeDown NS_SWIFT_NAME(volumeDown) = kVK_VolumeDown,
    SRKeyCodeMute NS_SWIFT_NAME(mute) = kVK_Mute,
    SRKeyCodeF18 NS_SWIFT_NAME(f18) = kVK_F18,
    SRKeyCodeF19 NS_SWIFT_NAME(f19) = kVK_F19,
    SRKeyCodeF20 NS_SWIFT_NAME(f20) = kVK_F20,
    SRKeyCodeF5 NS_SWIFT_NAME(f5) = kVK_F5,
    SRKeyCodeF6 NS_SWIFT_NAME(f6) = kVK_F6,
    SRKeyCodeF7 NS_SWIFT_NAME(f7) = kVK_F7,
    SRKeyCodeF3 NS_SWIFT_NAME(f3) = kVK_F3,
    SRKeyCodeF8 NS_SWIFT_NAME(f8) = kVK_F8,
    SRKeyCodeF9 NS_SWIFT_NAME(f9) = kVK_F9,
    SRKeyCodeF11 NS_SWIFT_NAME(f11) = kVK_F11,
    SRKeyCodeF13 NS_SWIFT_NAME(f13) = kVK_F13,
    SRKeyCodeF16 NS_SWIFT_NAME(f16) = kVK_F16,
    SRKeyCodeF14 NS_SWIFT_NAME(f14) = kVK_F14,
    SRKeyCodeF10 NS_SWIFT_NAME(f10) = kVK_F10,
    SRKeyCodeF12 NS_SWIFT_NAME(f12) = kVK_F12,
    SRKeyCodeF15 NS_SWIFT_NAME(f15) = kVK_F15,
    SRKeyCodeHelp NS_SWIFT_NAME(help) = kVK_Help,
    SRKeyCodeHome NS_SWIFT_NAME(home) = kVK_Home,
    SRKeyCodePageUp NS_SWIFT_NAME(pageUp) = kVK_PageUp,
    SRKeyCodeForwardDelete NS_SWIFT_NAME(forwardDelete) = kVK_ForwardDelete,
    SRKeyCodeF4 NS_SWIFT_NAME(f4) = kVK_F4,
    SRKeyCodeEnd NS_SWIFT_NAME(end) = kVK_End,
    SRKeyCodeF2 NS_SWIFT_NAME(f2) = kVK_F2,
    SRKeyCodePageDown NS_SWIFT_NAME(pageDown) = kVK_PageDown,
    SRKeyCodeF1 NS_SWIFT_NAME(f1) = kVK_F1,
    SRKeyCodeLeftArrow NS_SWIFT_NAME(leftArrow) = kVK_LeftArrow,
    SRKeyCodeRightArrow NS_SWIFT_NAME(rightArrow) = kVK_RightArrow,
    SRKeyCodeDownArrow NS_SWIFT_NAME(downArrow) = kVK_DownArrow,
    SRKeyCodeUpArrow NS_SWIFT_NAME(upArrow) = kVK_UpArrow,

    SRKeyCodeISOSection NS_SWIFT_NAME(isoSection) = kVK_ISO_Section,

    SRKeyCodeJISYen NS_SWIFT_NAME(jisYen) = kVK_JIS_Yen,
    SRKeyCodeJISUnderscore NS_SWIFT_NAME(jisUnderscore) = kVK_JIS_Underscore,
    SRKeyCodeJISKeypadComma NS_SWIFT_NAME(jisKeypadComma) = kVK_JIS_KeypadComma,
    SRKeyCodeJISEisu NS_SWIFT_NAME(jisEisu) = kVK_JIS_Eisu,
    SRKeyCodeJISKana NS_SWIFT_NAME(jisKana) = kVK_JIS_Kana
} NS_SWIFT_NAME(KeyCode);


/*!
 NSString version of SRModifierFlagGlyph

 @seealso SRModifierFlagGlyph
 */
typedef NSString *SRModifierFlagString NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(ModifierFlagString);
extern SRModifierFlagString const SRModifierFlagStringCommand;
extern SRModifierFlagString const SRModifierFlagStringOption;
extern SRModifierFlagString const SRModifierFlagStringShift;
extern SRModifierFlagString const SRModifierFlagStringControl;


/*!
 Convert a unichar literal into a NSString.
 */
NS_SWIFT_NAME(unicharToString(_:))
NS_INLINE NSString * SRUnicharToString(unichar aChar)
{
    return [NSString stringWithFormat:@"%C", aChar];
}


/*!
 Convert Carbon modifier flags to Cocoa.
 */
NS_SWIFT_NAME(carbonToCocoaFlags(_:))
NS_INLINE NSEventModifierFlags SRCarbonToCocoaFlags(UInt32 aCarbonFlags)
{
    NSEventModifierFlags cocoaFlags = 0;

    if (aCarbonFlags & cmdKey)
        cocoaFlags |= NSEventModifierFlagCommand;

    if (aCarbonFlags & optionKey)
        cocoaFlags |= NSEventModifierFlagOption;

    if (aCarbonFlags & controlKey)
        cocoaFlags |= NSEventModifierFlagControl;

    if (aCarbonFlags & shiftKey)
        cocoaFlags |= NSEventModifierFlagShift;

    return cocoaFlags;
}

/*!
 Convert Cocoa modifier flags to Carbon.
 */
NS_SWIFT_NAME(cocoaToCarbonFlags(_:))
NS_INLINE UInt32 SRCocoaToCarbonFlags(NSEventModifierFlags aCocoaFlags)
{
    UInt32 carbonFlags = 0;

    if (aCocoaFlags & NSEventModifierFlagCommand)
        carbonFlags |= cmdKey;

    if (aCocoaFlags & NSEventModifierFlagOption)
        carbonFlags |= optionKey;

    if (aCocoaFlags & NSEventModifierFlagControl)
        carbonFlags |= controlKey;

    if (aCocoaFlags & NSEventModifierFlagShift)
        carbonFlags |= shiftKey;

    return carbonFlags;
}


/*!
 Return Bundle where resources can be found.

 @throws NSInternalInconsistencyException

 @discussion Throws NSInternalInconsistencyException if bundle cannot be found.
 */
NS_SWIFT_NAME(shortcutRecorderBundle())
NSBundle * SRBundle(void);


/*!
 Convenience method to get localized string from the framework bundle.
 */
NS_SWIFT_NAME(shortcutRecorderLocalizedString(forKey:))
NSString * SRLoc(NSString * _Nullable aKey) __attribute__((annotate("returns_localized_nsstring")));


/*!
 Convenience method to get image from the framework bundle.
 */
NS_SWIFT_NAME(shortcutRecorderImage(forResource:))
NSImage * _Nullable SRImage(NSString * _Nullable anImageName);


@interface NSObject (SRCommon)

/*!
 Uses -isEqual: of the most specialized class of the same hierarchy to maintain transitivity and associativity.

 In the root class that overrides -isEqual:

 - (BOOL)isEqualTo<Class>:(<Class> *)anObject
 {
     if (anObject == self)
         return YES;
     else if (![anObject isKindOfClass:<Class>.class])
         return NO;
     else
         return <memberwise comparison>;
 }

 - (BOOL)isEqual:(NSObject *)anObject
 {
     return [self SR_isEqual:anObject usingSelector:@selector(isEqualTo<Class>:) ofCommonAncestor:<Class>.class];
 }

 In subsequent subclasses of the root class that extend equality test:

 - (BOOL)isEqualTo<Class>:(<Class> *)anObject
 {
     if (anObject == self)
         return YES;
     else if (![anObject isKindOfClass:self.class])
         return NO;
     else if (![super isEqualTo<Class>:anObject])
         return NO;
     else
         return <memberwise comparison>;
 }
 */
- (BOOL)SR_isEqual:(nullable NSObject *)anObject usingSelector:(SEL)aSelector ofCommonAncestor:(Class)anAncestor;

@end

NS_ASSUME_NONNULL_END
