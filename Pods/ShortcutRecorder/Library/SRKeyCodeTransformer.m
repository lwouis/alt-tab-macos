//
//  Copyright 2012 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <os/trace.h>
#import <os/activity.h>

#import "SRCommon.h"
#import "SRShortcut.h"
#import "SRKeyCodeTransformer.h"


/*!
 Return a retained isntance of Keyboard Layout Input Source.
 */
typedef TISInputSourceRef (*_SRKeyCodeTransformerCacheInputSourceCreate)(void);


@interface _SRKeyCodeTranslatorCacheKey : NSObject <NSCopying>
@property (copy, readonly) NSString *identifier;
@property (readonly) NSEventModifierFlags implicitModifierFlags;
@property (readonly) NSEventModifierFlags explicitModifierFlags;
@property (readonly) SRKeyCode keyCode;
- (instancetype)initWithIdentifier:(NSString *)anIdentifier
             implicitModifierFlags:(NSEventModifierFlags)anImplicitModifierFlags
             explicitModifierFlags:(NSEventModifierFlags)anExplicitModifierFlags
                           keyCode:(SRKeyCode)aKeyCode;
@end


@implementation _SRKeyCodeTranslatorCacheKey

- (instancetype)initWithIdentifier:(NSString *)anIdentifier
             implicitModifierFlags:(NSEventModifierFlags)anImplicitModifierFlags
             explicitModifierFlags:(NSEventModifierFlags)anExplicitModifierFlags
                           keyCode:(SRKeyCode)aKeyCode
{
    self = [super init];

    if (self)
    {
        _identifier = [anIdentifier copy];
        _implicitModifierFlags = anImplicitModifierFlags & SRCocoaModifierFlagsMask;
        _explicitModifierFlags = anExplicitModifierFlags & SRCocoaModifierFlagsMask;
        _keyCode = aKeyCode;
    }

    return self;
}

- (id)copyWithZone:(NSZone *)aZone
{
    return self;
}

- (BOOL)isEqual:(_SRKeyCodeTranslatorCacheKey *)anObject
{
    return self.keyCode == anObject.keyCode &&
        self.explicitModifierFlags == anObject.explicitModifierFlags &&
        self.implicitModifierFlags == anObject.implicitModifierFlags &&
        [self.identifier isEqual:anObject.identifier];
}

- (NSUInteger)hash
{
    NSUInteger implicitFlagsBitSize = 4;
    NSUInteger explicitFlagsBitSize = 4;
    NSUInteger keyCodeBitSize = sizeof(SRKeyCode) * CHAR_BIT;

    NSUInteger identifierHash = _identifier.hash;
    NSUInteger implicitFlagsHash = _implicitModifierFlags >> 17;
    NSUInteger explicitFlagsHash = _explicitModifierFlags >> 17;
    NSUInteger keyCodeHash = _keyCode;

    return keyCodeHash |
        (implicitFlagsHash << keyCodeBitSize) |
        (explicitFlagsHash << (keyCodeBitSize + implicitFlagsBitSize)) |
        (identifierHash << (keyCodeBitSize + implicitFlagsBitSize + explicitFlagsBitSize));
}

@end


/*!
 Cache of the key code translation with respect to input source identifier.
 */
@interface _SRKeyCodeTranslator : NSObject

@property (class, readonly) _SRKeyCodeTranslator *shared;
@property (readonly) _SRKeyCodeTransformerCacheInputSourceCreate inputSourceCreator;
@property (readonly) id inputSource;
/*!
 @param aCreator Lazily instantiates an instance of input source.
 */
- (instancetype)initWithInputSourceCreator:(_SRKeyCodeTransformerCacheInputSourceCreate)aCreator NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithInputSource:(id)anInputSource NS_DESIGNATED_INITIALIZER;
- (nullable NSString *)translateKeyCode:(SRKeyCode)aKeyCode
                  implicitModifierFlags:(NSEventModifierFlags)anImplicitModifierFlags
                  explicitModifierFlags:(NSEventModifierFlags)anExplicitModifierFlags
                             usingCache:(BOOL)anIsUsingCache;
@end


@implementation _SRKeyCodeTranslator
{
    NSCache<_SRKeyCodeTranslatorCacheKey *, NSString *> *_translationCache;
    id _inputSource;
}

+ (_SRKeyCodeTranslator *)shared
{
    static _SRKeyCodeTranslator *Cache = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Cache = [_SRKeyCodeTranslator new];
    });
    return Cache;
}

- (instancetype)init
{
    return [self initWithInputSourceCreator:TISCopyCurrentKeyboardLayoutInputSource];
}

- (instancetype)initWithInputSourceCreator:(_SRKeyCodeTransformerCacheInputSourceCreate)aCreator
{
    self = [super init];

    if (self)
    {
        _inputSourceCreator = aCreator;
        _translationCache = [NSCache new];
    }

    return self;
}

- (instancetype)initWithInputSource:(id)anInputSource
{
    self = [super init];

    if (self)
    {
        _inputSource = anInputSource;
        _translationCache = [NSCache new];
    }

    return self;
}

- (id)inputSource
{
    if (_inputSource)
        return _inputSource;
    else
        return (__bridge_transfer id)_inputSourceCreator();
}

- (nullable NSString *)translateKeyCode:(SRKeyCode)aKeyCode
                  implicitModifierFlags:(NSEventModifierFlags)anImplicitModifierFlags
                  explicitModifierFlags:(NSEventModifierFlags)anExplicitModifierFlags
                             usingCache:(BOOL)anIsUsingCache
{
    if (aKeyCode == SRKeyCodeNone)
        return @"";

    anImplicitModifierFlags &= SRCocoaModifierFlagsMask;
    anExplicitModifierFlags &= SRCocoaModifierFlagsMask;

    TISInputSourceRef inputSource = (__bridge TISInputSourceRef)self.inputSource;

    if (!inputSource)
    {
        os_trace_error("#Critical Failed to create an input source");
        return nil;
    }

    _SRKeyCodeTranslatorCacheKey *cacheKey = nil;

    if (anIsUsingCache)
    {
        NSString *sourceIdentifier = (__bridge NSString *)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);

        if (sourceIdentifier)
        {
            cacheKey = [[_SRKeyCodeTranslatorCacheKey alloc] initWithIdentifier:sourceIdentifier
                                                          implicitModifierFlags:anImplicitModifierFlags
                                                          explicitModifierFlags:anExplicitModifierFlags
                                                                        keyCode:aKeyCode];
        }
        else
            os_trace_error("#Error Input source misses an ID");
    }

    @synchronized (self)
    {
        NSString *translation = nil;

        if (cacheKey)
        {
            translation = [_translationCache objectForKey:cacheKey];

            if (translation)
            {
                os_trace_debug("Translation cache hit");
                return translation;
            }
            else
                os_trace_debug("Translation cache miss");
        }

        CFDataRef layoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData);
        const UCKeyboardLayout *keyLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
        static const UniCharCount MaxLength = 255;
        UniCharCount actualLength = 0;
        UniChar chars[MaxLength] = {0};
        UInt32 deadKeyState = 0;
        OSStatus error = UCKeyTranslate(keyLayout,
                                        aKeyCode,
                                        kUCKeyActionDisplay,
                                        SRCocoaToCarbonFlags(anImplicitModifierFlags) >> 8,
                                        LMGetKbdType(),
                                        kUCKeyTranslateNoDeadKeysBit,
                                        &deadKeyState,
                                        sizeof(chars) / sizeof(UniChar),
                                        &actualLength,
                                        chars);
        if (error != noErr)
        {
            os_trace_error("#Error Unable to translate keyCode %hu and modifierFlags %lu: %d",
                           aKeyCode,
                           anImplicitModifierFlags,
                           error);
            return nil;
        }
        else if (actualLength == 0)
        {
            os_trace_debug("#Error No translation exists for keyCode %hu and modifierFlags %lu",
                           aKeyCode,
                           anImplicitModifierFlags);
            return nil;
        }

        translation = [NSString stringWithCharacters:chars length:actualLength];

        if (cacheKey)
            [_translationCache setObject:translation forKey:cacheKey];

        return translation;
    }
}

@end


/*!
 ASCII Cache of the key code translation with respect to input source identifier capable of reverse transform.
 */
@interface _SRKeyCodeASCIITranslator : _SRKeyCodeTranslator
@property (class, readonly) _SRKeyCodeASCIITranslator *shared;
- (nullable NSNumber *)keyCodeForTranslation:(NSString *)aTranslation;
@end


@implementation _SRKeyCodeASCIITranslator
{
    NSDictionary<NSString *, NSNumber *> *_translationToKeyCode;
    NSString *_inputSourceIdentifier;
}

+ (_SRKeyCodeASCIITranslator *)shared
{
    static _SRKeyCodeASCIITranslator *Cache = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Cache = [[_SRKeyCodeASCIITranslator alloc] initWithInputSourceCreator:TISCopyCurrentASCIICapableKeyboardLayoutInputSource];
    });
    return Cache;
}

- (NSNumber *)keyCodeForTranslation:(NSString *)aTranslation
{
    NSAssert([aTranslation.lowercaseString isEqualToString:aTranslation], @"aTranslation must be a lowercase string");

    TISInputSourceRef inputSource = self.inputSourceCreator();

    if (!inputSource)
    {
        os_trace_error("#Critical Failed to create an input source");
        return nil;
    }

    inputSource = (TISInputSourceRef)CFAutorelease(inputSource);

    NSString *sourceIdentifier = (__bridge NSString *)TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID);

    if (!sourceIdentifier)
    {
        os_trace_error("#Error Input source misses an ID");
        return nil;
    }

    @synchronized (self)
    {
        if ([_inputSourceIdentifier isEqualToString:sourceIdentifier])
            return _translationToKeyCode[aTranslation];

        os_trace_debug("Updating translation -> key code mapping");

        __auto_type knownKeyCodes = SRKeyCodeTransformer.knownKeyCodes;
        NSMutableDictionary *newTranslationToKeyCode = [NSMutableDictionary dictionaryWithCapacity:knownKeyCodes.count];

        for (NSNumber *keyCode in knownKeyCodes)
        {
            NSString *translation = [self translateKeyCode:keyCode.unsignedShortValue
                                     implicitModifierFlags:0
                                     explicitModifierFlags:0
                                                usingCache:YES];

            if (translation.length)
                newTranslationToKeyCode[translation] = keyCode;
        }

        _translationToKeyCode = [newTranslationToKeyCode copy];
        _inputSourceIdentifier = [sourceIdentifier copy];

        return _translationToKeyCode[aTranslation];
    }
}

@end


@interface SRKeyCodeTransformer ()
{
@protected
    _SRKeyCodeTranslator *_translator;
}

@end

#pragma mark -

@implementation SRKeyCodeTransformer

- (instancetype)init
{
    if (self.class == SRKeyCodeTransformer.class)
        return SRSymbolicKeyCodeTransformer.sharedTransformer;
    else
        return [super init];
}

- (instancetype)initWithInputSource:(id)anInputSource
{
    if (self.class == SRKeyCodeTransformer.class)
        return [[SRSymbolicKeyCodeTransformer alloc] initWithInputSource:anInputSource];
    else
    {
        self = [super init];

        if (self)
        {
            _translator = [[_SRKeyCodeTranslator alloc] initWithInputSource:anInputSource];
        }

        return self;
    }
}

#pragma mark Properties

+ (NSArray<NSNumber *> *)knownKeyCodes
{
    static NSArray<NSNumber *> *KnownKeyCodes = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        KnownKeyCodes = @[
            @(SRKeyCode0),
            @(SRKeyCode1),
            @(SRKeyCode2),
            @(SRKeyCode3),
            @(SRKeyCode4),
            @(SRKeyCode5),
            @(SRKeyCode6),
            @(SRKeyCode7),
            @(SRKeyCode8),
            @(SRKeyCode9),
            @(SRKeyCodeA),
            @(SRKeyCodeB),
            @(SRKeyCodeBackslash),
            @(SRKeyCodeC),
            @(SRKeyCodeComma),
            @(SRKeyCodeD),
            @(SRKeyCodeE),
            @(SRKeyCodeEqual),
            @(SRKeyCodeF),
            @(SRKeyCodeG),
            @(SRKeyCodeGrave),
            @(SRKeyCodeH),
            @(SRKeyCodeI),
            @(SRKeyCodeJ),
            @(SRKeyCodeK),
            @(SRKeyCodeKeypad0),
            @(SRKeyCodeKeypad1),
            @(SRKeyCodeKeypad2),
            @(SRKeyCodeKeypad3),
            @(SRKeyCodeKeypad4),
            @(SRKeyCodeKeypad5),
            @(SRKeyCodeKeypad6),
            @(SRKeyCodeKeypad7),
            @(SRKeyCodeKeypad8),
            @(SRKeyCodeKeypad9),
            @(SRKeyCodeKeypadDecimal),
            @(SRKeyCodeKeypadDivide),
            @(SRKeyCodeKeypadEnter),
            @(SRKeyCodeKeypadEquals),
            @(SRKeyCodeKeypadMinus),
            @(SRKeyCodeKeypadMultiply),
            @(SRKeyCodeKeypadPlus),
            @(SRKeyCodeL),
            @(SRKeyCodeLeftBracket),
            @(SRKeyCodeM),
            @(SRKeyCodeMinus),
            @(SRKeyCodeN),
            @(SRKeyCodeO),
            @(SRKeyCodeP),
            @(SRKeyCodePeriod),
            @(SRKeyCodeQ),
            @(SRKeyCodeQuote),
            @(SRKeyCodeR),
            @(SRKeyCodeRightBracket),
            @(SRKeyCodeS),
            @(SRKeyCodeSemicolon),
            @(SRKeyCodeSlash),
            @(SRKeyCodeT),
            @(SRKeyCodeU),
            @(SRKeyCodeV),
            @(SRKeyCodeW),
            @(SRKeyCodeX),
            @(SRKeyCodeY),
            @(SRKeyCodeZ),
            @(SRKeyCodeDelete),
            @(SRKeyCodeDownArrow),
            @(SRKeyCodeEnd),
            @(SRKeyCodeEscape),
            @(SRKeyCodeF1),
            @(SRKeyCodeF2),
            @(SRKeyCodeF3),
            @(SRKeyCodeF4),
            @(SRKeyCodeF5),
            @(SRKeyCodeF6),
            @(SRKeyCodeF7),
            @(SRKeyCodeF8),
            @(SRKeyCodeF9),
            @(SRKeyCodeF10),
            @(SRKeyCodeF11),
            @(SRKeyCodeF12),
            @(SRKeyCodeF13),
            @(SRKeyCodeF14),
            @(SRKeyCodeF15),
            @(SRKeyCodeF16),
            @(SRKeyCodeF17),
            @(SRKeyCodeF18),
            @(SRKeyCodeF19),
            @(SRKeyCodeF20),
            @(SRKeyCodeForwardDelete),
            @(SRKeyCodeHelp),
            @(SRKeyCodeHome),
            @(SRKeyCodeISOSection),
            @(SRKeyCodeJISKeypadComma),
            @(SRKeyCodeJISUnderscore),
            @(SRKeyCodeJISYen),
            @(SRKeyCodeLeftArrow),
            @(SRKeyCodePageDown),
            @(SRKeyCodePageUp),
            @(SRKeyCodeReturn),
            @(SRKeyCodeRightArrow),
            @(SRKeyCodeSpace),
            @(SRKeyCodeTab),
            @(SRKeyCodeUpArrow)
        ];
    });

    return KnownKeyCodes;
}

+ (instancetype)sharedTransformer
{
    return SRSymbolicKeyCodeTransformer.sharedTransformer;
}

- (id)inputSource
{
    return _translator.inputSource;
}

#pragma mark Methods

- (NSString *)literalForKeyCode:(SRKeyCode)aValue
      withImplicitModifierFlags:(NSEventModifierFlags)anImplicitModifierFlags
          explicitModifierFlags:(NSEventModifierFlags)anExplicitModifierFlags
                layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    switch (aValue)
    {
        case SRKeyCodeF1:
            return @"F1";
        case SRKeyCodeF2:
            return @"F2";
        case SRKeyCodeF3:
            return @"F3";
        case SRKeyCodeF4:
            return @"F4";
        case SRKeyCodeF5:
            return @"F5";
        case SRKeyCodeF6:
            return @"F6";
        case SRKeyCodeF7:
            return @"F7";
        case SRKeyCodeF8:
            return @"F8";
        case SRKeyCodeF9:
            return @"F9";
        case SRKeyCodeF10:
            return @"F10";
        case SRKeyCodeF11:
            return @"F11";
        case SRKeyCodeF12:
            return @"F12";
        case SRKeyCodeF13:
            return @"F13";
        case SRKeyCodeF14:
            return @"F14";
        case SRKeyCodeF15:
            return @"F15";
        case SRKeyCodeF16:
            return @"F16";
        case SRKeyCodeF17:
            return @"F17";
        case SRKeyCodeF18:
            return @"F18";
        case SRKeyCodeF19:
            return @"F19";
        case SRKeyCodeF20:
            return @"F20";
        case SRKeyCodeSpace:
            return SRLoc(@"Space");
        case SRKeyCodeDelete:
            return aDirection == NSUserInterfaceLayoutDirectionRightToLeft ? SRKeyCodeStringDeleteRight : SRKeyCodeStringDeleteLeft;
        case SRKeyCodeForwardDelete:
            return aDirection == NSUserInterfaceLayoutDirectionRightToLeft ? SRKeyCodeStringDeleteLeft : SRKeyCodeStringDeleteRight;
        case SRKeyCodeKeypadClear:
            return SRKeyCodeStringPadClear;
        case SRKeyCodeLeftArrow:
            return SRKeyCodeStringLeftArrow;
        case SRKeyCodeRightArrow:
            return SRKeyCodeStringRightArrow;
        case SRKeyCodeUpArrow:
            return SRKeyCodeStringUpArrow;
        case SRKeyCodeDownArrow:
            return SRKeyCodeStringDownArrow;
        case SRKeyCodeEnd:
            return SRKeyCodeStringSoutheastArrow;
        case SRKeyCodeHome:
            return SRKeyCodeStringNorthwestArrow;
        case SRKeyCodeEscape:
            return SRKeyCodeStringEscape;
        case SRKeyCodePageDown:
            return SRKeyCodeStringPageDown;
        case SRKeyCodePageUp:
            return SRKeyCodeStringPageUp;
        case SRKeyCodeReturn:
            return SRKeyCodeStringReturnR2L;
        case SRKeyCodeKeypadEnter:
            return SRKeyCodeStringReturn;
        case SRKeyCodeTab:
        {
            if (anImplicitModifierFlags & NSEventModifierFlagShift)
                return aDirection == NSUserInterfaceLayoutDirectionRightToLeft ? SRKeyCodeStringTabRight : SRKeyCodeStringTabLeft;
            else
                return aDirection == NSUserInterfaceLayoutDirectionRightToLeft ? SRKeyCodeStringTabLeft : SRKeyCodeStringTabRight;
        }
        case SRKeyCodeHelp:
            return SRKeyCodeStringHelp;
        case SRKeyCodeJISUnderscore:
            return SRKeyCodeStringJISUnderscore;
        case SRKeyCodeJISKeypadComma:
            return SRKeyCodeStringJISComma;
        case SRKeyCodeJISYen:
            return SRKeyCodeStringJISYen;
        default:
            return [_translator translateKeyCode:aValue
                           implicitModifierFlags:anImplicitModifierFlags
                           explicitModifierFlags:anExplicitModifierFlags
                                      usingCache:YES].uppercaseString;
    }
}

- (NSString *)symbolForKeyCode:(SRKeyCode)aValue
     withImplicitModifierFlags:(NSEventModifierFlags)anImplicitModifierFlags
         explicitModifierFlags:(NSEventModifierFlags)anExplicitModifierFlags
               layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    switch (aValue)
    {
        case SRKeyCodeF1:
            return SRUnicharToString(NSF1FunctionKey);
        case SRKeyCodeF2:
            return SRUnicharToString(NSF2FunctionKey);
        case SRKeyCodeF3:
            return SRUnicharToString(NSF3FunctionKey);
        case SRKeyCodeF4:
            return SRUnicharToString(NSF4FunctionKey);
        case SRKeyCodeF5:
            return SRUnicharToString(NSF5FunctionKey);
        case SRKeyCodeF6:
            return SRUnicharToString(NSF6FunctionKey);
        case SRKeyCodeF7:
            return SRUnicharToString(NSF7FunctionKey);
        case SRKeyCodeF8:
            return SRUnicharToString(NSF8FunctionKey);
        case SRKeyCodeF9:
            return SRUnicharToString(NSF9FunctionKey);
        case SRKeyCodeF10:
            return SRUnicharToString(NSF10FunctionKey);
        case SRKeyCodeF11:
            return SRUnicharToString(NSF11FunctionKey);
        case SRKeyCodeF12:
            return SRUnicharToString(NSF12FunctionKey);
        case SRKeyCodeF13:
            return SRUnicharToString(NSF13FunctionKey);
        case SRKeyCodeF14:
            return SRUnicharToString(NSF14FunctionKey);
        case SRKeyCodeF15:
            return SRUnicharToString(NSF15FunctionKey);
        case SRKeyCodeF16:
            return SRUnicharToString(NSF16FunctionKey);
        case SRKeyCodeF17:
            return SRUnicharToString(NSF17FunctionKey);
        case SRKeyCodeF18:
            return SRUnicharToString(NSF18FunctionKey);
        case SRKeyCodeF19:
            return SRUnicharToString(NSF19FunctionKey);
        case SRKeyCodeF20:
            return SRUnicharToString(NSF20FunctionKey);
        case SRKeyCodeSpace:
            return SRUnicharToString(' ');
        case SRKeyCodeDelete:
            return SRUnicharToString(NSBackspaceCharacter);
        case SRKeyCodeForwardDelete:
            return SRUnicharToString(NSDeleteCharacter);
        case SRKeyCodeKeypadClear:
            return SRUnicharToString(NSClearLineFunctionKey);
        case SRKeyCodeLeftArrow:
            return SRUnicharToString(NSLeftArrowFunctionKey);
        case SRKeyCodeRightArrow:
            return SRUnicharToString(NSRightArrowFunctionKey);
        case SRKeyCodeUpArrow:
            return SRUnicharToString(NSUpArrowFunctionKey);
        case SRKeyCodeDownArrow:
            return SRUnicharToString(NSDownArrowFunctionKey);
        case SRKeyCodeEnd:
            return SRUnicharToString(NSEndFunctionKey);
        case SRKeyCodeHome:
            return SRUnicharToString(NSHomeFunctionKey);
        case SRKeyCodeEscape:
            return SRUnicharToString('\e');
        case SRKeyCodePageDown:
            return SRUnicharToString(NSPageDownFunctionKey);
        case SRKeyCodePageUp:
            return SRUnicharToString(NSPageUpFunctionKey);
        case SRKeyCodeReturn:
            return SRUnicharToString(NSCarriageReturnCharacter);
        case SRKeyCodeKeypadEnter:
            return SRUnicharToString(NSEnterCharacter);
        case SRKeyCodeTab:
            return SRUnicharToString(NSTabCharacter);
        case SRKeyCodeHelp:
            return SRUnicharToString(NSHelpFunctionKey);
        case SRKeyCodeJISUnderscore:
            return SRKeyCodeStringJISUnderscore;
        case SRKeyCodeJISKeypadComma:
            return SRKeyCodeStringJISComma;
        case SRKeyCodeJISYen:
            return SRKeyCodeStringJISYen;
        default:
            return [_translator translateKeyCode:aValue
                           implicitModifierFlags:anImplicitModifierFlags
                           explicitModifierFlags:anExplicitModifierFlags
                                      usingCache:YES];
    }
}

- (NSString *)transformedValue:(NSNumber *)aValue
     withImplicitModifierFlags:(NSNumber *)anImplicitModifierFlags
         explicitModifierFlags:(NSNumber *)anExplicitModifierFlags
               layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    return nil;
}

#pragma mark Deprecated

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

+ (instancetype)sharedASCIITransformer
{
    return SRASCIISymbolicKeyCodeTransformer.sharedTransformer;
}

+ (instancetype)sharedPlainTransformer
{
    return SRLiteralKeyCodeTransformer.sharedTransformer;
}

+ (SRKeyCodeTransformer *)sharedPlainASCIITransformer
{
    return SRASCIILiteralKeyCodeTransformer.sharedTransformer;
}

+ (NSDictionary<NSNumber *, NSString *> *)specialKeyCodeToSymbolMapping
{
    // Most of these keys are system constans.
    // Values for rest of the keys were given by setting key equivalents in IB.
    static NSDictionary *Mapping = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Mapping = @{
            @(SRKeyCodeF1): SRUnicharToString(NSF1FunctionKey),
            @(SRKeyCodeF2): SRUnicharToString(NSF2FunctionKey),
            @(SRKeyCodeF3): SRUnicharToString(NSF3FunctionKey),
            @(SRKeyCodeF4): SRUnicharToString(NSF4FunctionKey),
            @(SRKeyCodeF5): SRUnicharToString(NSF5FunctionKey),
            @(SRKeyCodeF6): SRUnicharToString(NSF6FunctionKey),
            @(SRKeyCodeF7): SRUnicharToString(NSF7FunctionKey),
            @(SRKeyCodeF8): SRUnicharToString(NSF8FunctionKey),
            @(SRKeyCodeF9): SRUnicharToString(NSF9FunctionKey),
            @(SRKeyCodeF10): SRUnicharToString(NSF10FunctionKey),
            @(SRKeyCodeF11): SRUnicharToString(NSF11FunctionKey),
            @(SRKeyCodeF12): SRUnicharToString(NSF12FunctionKey),
            @(SRKeyCodeF13): SRUnicharToString(NSF13FunctionKey),
            @(SRKeyCodeF14): SRUnicharToString(NSF14FunctionKey),
            @(SRKeyCodeF15): SRUnicharToString(NSF15FunctionKey),
            @(SRKeyCodeF16): SRUnicharToString(NSF16FunctionKey),
            @(SRKeyCodeF17): SRUnicharToString(NSF17FunctionKey),
            @(SRKeyCodeF18): SRUnicharToString(NSF18FunctionKey),
            @(SRKeyCodeF19): SRUnicharToString(NSF19FunctionKey),
            @(SRKeyCodeF20): SRUnicharToString(NSF20FunctionKey),
            @(SRKeyCodeSpace): SRUnicharToString(' '),
            @(SRKeyCodeDelete): SRUnicharToString(NSBackspaceCharacter),
            @(SRKeyCodeForwardDelete): SRUnicharToString(NSDeleteCharacter),
            @(SRKeyCodeKeypadClear): SRUnicharToString(NSClearLineFunctionKey),
            @(SRKeyCodeLeftArrow): SRUnicharToString(NSLeftArrowFunctionKey),
            @(SRKeyCodeRightArrow): SRUnicharToString(NSRightArrowFunctionKey),
            @(SRKeyCodeUpArrow): SRUnicharToString(NSUpArrowFunctionKey),
            @(SRKeyCodeDownArrow): SRUnicharToString(NSDownArrowFunctionKey),
            @(SRKeyCodeEnd): SRUnicharToString(NSEndFunctionKey),
            @(SRKeyCodeHome): SRUnicharToString(NSHomeFunctionKey),
            @(SRKeyCodeEscape): SRUnicharToString('\e'),
            @(SRKeyCodePageDown): SRUnicharToString(NSPageDownFunctionKey),
            @(SRKeyCodePageUp): SRUnicharToString(NSPageUpFunctionKey),
            @(SRKeyCodeReturn): SRUnicharToString(NSCarriageReturnCharacter),
            @(SRKeyCodeKeypadEnter): SRUnicharToString(NSEnterCharacter),
            @(SRKeyCodeTab): SRUnicharToString(NSTabCharacter),
            @(SRKeyCodeHelp): SRUnicharToString(NSHelpFunctionKey)
        };
    });
    return Mapping;
}

+ (NSDictionary<NSNumber *, NSString *> *)specialKeyCodeToLiteralMapping
{
    static NSDictionary *Mapping = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Mapping = @{
            @(SRKeyCodeF1): @"F1",
            @(SRKeyCodeF2): @"F2",
            @(SRKeyCodeF3): @"F3",
            @(SRKeyCodeF4): @"F4",
            @(SRKeyCodeF5): @"F5",
            @(SRKeyCodeF6): @"F6",
            @(SRKeyCodeF7): @"F7",
            @(SRKeyCodeF8): @"F8",
            @(SRKeyCodeF9): @"F9",
            @(SRKeyCodeF10): @"F10",
            @(SRKeyCodeF11): @"F11",
            @(SRKeyCodeF12): @"F12",
            @(SRKeyCodeF13): @"F13",
            @(SRKeyCodeF14): @"F14",
            @(SRKeyCodeF15): @"F15",
            @(SRKeyCodeF16): @"F16",
            @(SRKeyCodeF17): @"F17",
            @(SRKeyCodeF18): @"F18",
            @(SRKeyCodeF19): @"F19",
            @(SRKeyCodeF20): @"F20",
            @(SRKeyCodeSpace): SRLoc(@"Space"),
            @(SRKeyCodeDelete): SRKeyCodeStringDeleteLeft,
            @(SRKeyCodeForwardDelete): SRKeyCodeStringDeleteRight,
            @(SRKeyCodeKeypadClear): SRKeyCodeStringPadClear,
            @(SRKeyCodeLeftArrow): SRKeyCodeStringLeftArrow,
            @(SRKeyCodeRightArrow): SRKeyCodeStringRightArrow,
            @(SRKeyCodeUpArrow): SRKeyCodeStringUpArrow,
            @(SRKeyCodeDownArrow): SRKeyCodeStringDownArrow,
            @(SRKeyCodeEnd): SRKeyCodeStringSoutheastArrow,
            @(SRKeyCodeHome): SRKeyCodeStringNorthwestArrow,
            @(SRKeyCodeEscape): SRKeyCodeStringEscape,
            @(SRKeyCodePageDown): SRKeyCodeStringPageDown,
            @(SRKeyCodePageUp): SRKeyCodeStringPageUp,
            @(SRKeyCodeReturn): SRKeyCodeStringReturnR2L,
            @(SRKeyCodeKeypadEnter): SRKeyCodeStringReturn,
            @(SRKeyCodeTab): SRKeyCodeStringTabRight,
            @(SRKeyCodeHelp): @"?⃝"
        };
    });
    return Mapping;
}

- (instancetype)initWithASCIICapableKeyboardInputSource:(BOOL)aUsesASCII plainStrings:(BOOL)aUsesPlainStrings
{
    if (aUsesASCII && aUsesPlainStrings)
        return SRASCIILiteralKeyCodeTransformer.sharedTransformer;
    else if (aUsesASCII)
        return SRASCIISymbolicKeyCodeTransformer.sharedTransformer;
    else if (aUsesPlainStrings)
        return SRLiteralKeyCodeTransformer.sharedTransformer;
    else
        return SRSymbolicKeyCodeTransformer.sharedTransformer;
}

- (BOOL)usesASCIICapableKeyboardInputSource
{
    return [self isKindOfClass:SRASCIILiteralKeyCodeTransformer.class] || [self isKindOfClass:SRASCIISymbolicKeyCodeTransformer.class];
}

- (BOOL)usesPlainStrings
{
    return [self isKindOfClass:SRLiteralKeyCodeTransformer.class] || [self isKindOfClass:SRASCIILiteralKeyCodeTransformer.class];
}

- (NSString *)transformedValue:(NSNumber *)aValue withModifierFlags:(NSNumber *)aModifierFlags
{
    return [self transformedValue:aValue
        withImplicitModifierFlags:aModifierFlags
            explicitModifierFlags:nil
                  layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
}

- (NSString *)transformedValue:(NSNumber *)aValue
     withImplicitModifierFlags:(NSNumber *)anImplicitModifierFlags
         explicitModifierFlags:(NSNumber *)anExplicitModifierFlags
{
    return [self transformedValue:aValue
        withImplicitModifierFlags:anImplicitModifierFlags
            explicitModifierFlags:anExplicitModifierFlags
                  layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
}

- (NSString *)transformedSpecialKeyCode:(NSNumber *)aKeyCode
              withExplicitModifierFlags:(NSNumber *)anExplicitModifierFlags
{
    return [self transformedValue:aKeyCode
        withImplicitModifierFlags:nil
            explicitModifierFlags:anExplicitModifierFlags
                  layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
}

- (BOOL)isKeyCodeSpecial:(SRKeyCode)aKeyCode
{
    return self.class.specialKeyCodeToSymbolMapping[@(aKeyCode)] != nil;
}

#pragma clang diagnostic pop

#pragma mark NSValueTransformer

+ (Class)transformedValueClass;
{
    return [NSString class];
}

- (NSString *)transformedValue:(NSNumber *)aValue
{
    if ([aValue isKindOfClass:SRShortcut.class])
    {
        return [self transformedValue:@([(SRShortcut *)aValue keyCode])
            withImplicitModifierFlags:nil
                explicitModifierFlags:@([(SRShortcut *)aValue modifierFlags])
                      layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
    }
    else
    {
        return [self transformedValue:aValue
            withImplicitModifierFlags:nil
                explicitModifierFlags:nil
                      layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
    }
}

- (NSNumber *)reverseTransformedValue:(NSString *)aValue
{
    return nil;
}

@end

#pragma mark -

@implementation SRLiteralKeyCodeTransformer

+ (SRLiteralKeyCodeTransformer *)sharedTransformer
{
    static SRLiteralKeyCodeTransformer *Transformer = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Transformer = [SRLiteralKeyCodeTransformer new];
    });
    return Transformer;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _translator = _SRKeyCodeTranslator.shared;
    }

    return self;
}

- (NSString *)transformedValue:(NSNumber *)aValue
     withImplicitModifierFlags:(NSNumber *)anImplicitModifierFlags
         explicitModifierFlags:(NSNumber *)anExplicitModifierFlags
               layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    __block NSString *result = nil;
    os_activity_initiate("Key Code -> Literal", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (![aValue isKindOfClass:NSNumber.class])
        {
            os_trace_error("#Error Invalid key code");
            return;
        }

        result = [self literalForKeyCode:aValue.unsignedShortValue
               withImplicitModifierFlags:anImplicitModifierFlags.unsignedIntegerValue
                   explicitModifierFlags:anExplicitModifierFlags.unsignedIntegerValue
                         layoutDirection:aDirection];
    });

    return result;
}

@end

#pragma mark -

@implementation SRSymbolicKeyCodeTransformer

+ (SRSymbolicKeyCodeTransformer *)sharedTransformer
{
    static SRSymbolicKeyCodeTransformer *Transformer = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Transformer = [SRSymbolicKeyCodeTransformer new];
    });
    return Transformer;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _translator = _SRKeyCodeTranslator.shared;
    }

    return self;
}

- (NSString *)transformedValue:(NSNumber *)aValue
     withImplicitModifierFlags:(NSNumber *)anImplicitModifierFlags
         explicitModifierFlags:(NSNumber *)anExplicitModifierFlags
               layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    __block NSString *result = nil;
    os_activity_initiate("Key Code -> Symbol", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (![aValue isKindOfClass:NSNumber.class])
        {
            os_trace_error("#Error Invalid key code");
            return;
        }

        result = [self symbolForKeyCode:aValue.unsignedShortValue
              withImplicitModifierFlags:anImplicitModifierFlags.unsignedIntegerValue
                  explicitModifierFlags:anExplicitModifierFlags.unsignedIntegerValue
                        layoutDirection:aDirection];
    });

    return result;
}

@end

#pragma mark -

@implementation SRASCIILiteralKeyCodeTransformer

+ (SRASCIILiteralKeyCodeTransformer *)sharedTransformer
{
    static SRASCIILiteralKeyCodeTransformer *Transformer = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Transformer = [SRASCIILiteralKeyCodeTransformer new];
    });
    return Transformer;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _translator = _SRKeyCodeASCIITranslator.shared;
    }

    return self;
}

- (NSString *)transformedValue:(NSNumber *)aValue
     withImplicitModifierFlags:(NSNumber *)anImplicitModifierFlags
         explicitModifierFlags:(NSNumber *)anExplicitModifierFlags
               layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    __block NSString *result = nil;
    os_activity_initiate("Key Code -> ASCII Literal", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (![aValue isKindOfClass:NSNumber.class])
        {
            os_trace_error("#Error Invalid key code");
            return;
        }

        result = [self literalForKeyCode:aValue.unsignedShortValue
               withImplicitModifierFlags:anImplicitModifierFlags.unsignedIntegerValue
                   explicitModifierFlags:anExplicitModifierFlags.unsignedIntegerValue
                         layoutDirection:aDirection];
    });

    return result;
}

#pragma mark NSValueTransformer

+ (BOOL)allowsReverseTransformation
{
    return YES;
}

- (NSNumber *)reverseTransformedValue:(NSString *)aValue
{
    __block NSNumber *result = nil;
    os_activity_initiate("ASCII Literal -> Key Code", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (![aValue isKindOfClass:NSString.class] || !aValue.length)
        {
            os_trace_error("#Error Invalid ASCII literal");
            return;
        }

        NSString *lowercaseValue = aValue.lowercaseString;

        if (lowercaseValue.length == 1)
        {
            unichar glyph = [lowercaseValue characterAtIndex:0];

            switch (glyph)
            {
                case SRKeyCodeGlyphTabRight:
                case SRKeyCodeGlyphTabLeft:
                    result = @(SRKeyCodeTab);
                    break;
                case SRKeyCodeGlyphReturn:
                    result = @(SRKeyCodeKeypadEnter);
                    break;
                case SRKeyCodeGlyphReturnR2L:
                    result = @(SRKeyCodeReturn);
                    break;
                case SRKeyCodeGlyphDeleteLeft:
                    result = @(SRKeyCodeDelete);
                    break;
                case SRKeyCodeGlyphDeleteRight:
                    result = @(SRKeyCodeForwardDelete);
                    break;
                case SRKeyCodeGlyphPadClear:
                    result = @(SRKeyCodeKeypadClear);
                    break;
                case SRKeyCodeGlyphLeftArrow:
                    result = @(SRKeyCodeLeftArrow);
                    break;
                case SRKeyCodeGlyphRightArrow:
                    result = @(SRKeyCodeRightArrow);
                    break;
                case SRKeyCodeGlyphUpArrow:
                    result = @(SRKeyCodeUpArrow);
                    break;
                case SRKeyCodeGlyphDownArrow:
                    result = @(SRKeyCodeDownArrow);
                    break;
                case SRKeyCodeGlyphPageDown:
                    result = @(SRKeyCodePageDown);
                    break;
                case SRKeyCodeGlyphPageUp:
                    result = @(SRKeyCodePageUp);
                    break;
                case SRKeyCodeGlyphNorthwestArrow:
                    result = @(SRKeyCodeHome);
                    break;
                case SRKeyCodeGlyphSoutheastArrow:
                    result = @(SRKeyCodeEnd);
                    break;
                case SRKeyCodeGlyphEscape:
                    result = @(SRKeyCodeEscape);
                    break;
                case SRKeyCodeGlyphSpace:
                    result = @(SRKeyCodeSpace);
                    break;
                case SRKeyCodeGlyphJISUnderscore:
                    result = @(SRKeyCodeJISUnderscore);
                    break;
                case SRKeyCodeGlyphJISComma:
                    result = @(SRKeyCodeJISKeypadComma);
                    break;
                case SRKeyCodeGlyphJISYen:
                    result = @(SRKeyCodeJISYen);
                    break;
                case SRKeyCodeGlyphANSI0:
                    result = @(SRKeyCode0);
                    break;
                case SRKeyCodeGlyphANSI1:
                    result = @(SRKeyCode1);
                    break;
                case SRKeyCodeGlyphANSI2:
                    result = @(SRKeyCode2);
                    break;
                case SRKeyCodeGlyphANSI3:
                    result = @(SRKeyCode3);
                    break;
                case SRKeyCodeGlyphANSI4:
                    result = @(SRKeyCode4);
                    break;
                case SRKeyCodeGlyphANSI5:
                    result = @(SRKeyCode5);
                    break;
                case SRKeyCodeGlyphANSI6:
                    result = @(SRKeyCode6);
                    break;
                case SRKeyCodeGlyphANSI7:
                    result = @(SRKeyCode7);
                    break;
                case SRKeyCodeGlyphANSI8:
                    result = @(SRKeyCode8);
                    break;
                case SRKeyCodeGlyphANSI9:
                    result = @(SRKeyCode9);
                    break;
                case SRKeyCodeGlyphANSIEqual:
                    result = @(SRKeyCodeEqual);
                    break;
                case SRKeyCodeGlyphANSIMinus:
                    result = @(SRKeyCodeMinus);
                    break;
                case SRKeyCodeGlyphANSISlash:
                    result = @(SRKeyCodeSlash);
                    break;
                case SRKeyCodeGlyphANSIPeriod:
                    result = @(SRKeyCodePeriod);
                    break;
                default:
                    break;
            }
        }
        else if ((lowercaseValue.length == 2 || lowercaseValue.length == 3) & [lowercaseValue hasPrefix:@"f"])
        {
            NSInteger fNumber = [lowercaseValue substringFromIndex:1].integerValue;
            if (fNumber > 0 && ((lowercaseValue.length == 2 && fNumber < 10) || (lowercaseValue.length == 3 && fNumber >= 10)))
            {
                switch (fNumber)
                {
                    case 1:
                        result = @(SRKeyCodeF1);
                        break;
                    case 2:
                        result = @(SRKeyCodeF2);
                        break;
                    case 3:
                        result = @(SRKeyCodeF3);
                        break;
                    case 4:
                        result = @(SRKeyCodeF4);
                        break;
                    case 5:
                        result = @(SRKeyCodeF5);
                        break;
                    case 6:
                        result = @(SRKeyCodeF6);
                        break;
                    case 7:
                        result = @(SRKeyCodeF7);
                        break;
                    case 8:
                        result = @(SRKeyCodeF8);
                        break;
                    case 9:
                        result = @(SRKeyCodeF9);
                        break;
                    case 10:
                        result = @(SRKeyCodeF10);
                        break;
                    case 11:
                        result = @(SRKeyCodeF11);
                        break;
                    case 12:
                        result = @(SRKeyCodeF12);
                        break;
                    case 13:
                        result = @(SRKeyCodeF13);
                        break;
                    case 14:
                        result = @(SRKeyCodeF14);
                        break;
                    case 15:
                        result = @(SRKeyCodeF15);
                        break;
                    case 16:
                        result = @(SRKeyCodeF16);
                        break;
                    case 17:
                        result = @(SRKeyCodeF17);
                        break;
                    case 18:
                        result = @(SRKeyCodeF18);
                        break;
                    case 19:
                        result = @(SRKeyCodeF19);
                        break;
                    case 20:
                        result = @(SRKeyCodeF20);
                        break;
                    default:
                        break;
                }
            }
        }
        else
        {
            if ([lowercaseValue caseInsensitiveCompare:SRLoc(@"Space")] == NSOrderedSame ||
                [lowercaseValue isEqualToString:@"space"])
            {
                result = @(SRKeyCodeSpace);
            }
            else if ([lowercaseValue isEqualToString:@"esc"] || [lowercaseValue isEqualToString:@"escape"])
                result = @(SRKeyCodeEscape);
            else if ([lowercaseValue isEqualToString:@"tab"])
                result = @(SRKeyCodeTab);
            else if ([lowercaseValue isEqualToString:@"help"] || [lowercaseValue isEqualToString:@"?⃝"])
                result = @(SRKeyCodeHelp);
            else if ([lowercaseValue isEqualToString:@"enter"])
                result = @(SRKeyCodeReturn);
        }

        if (result == nil)
            result = [(_SRKeyCodeASCIITranslator *)self->_translator keyCodeForTranslation:lowercaseValue];
    });

    if (!result)
    {
        os_trace_error("#Error Invalid value for reverse transformation");
    }

    return result;
}

@end

#pragma mark -

@implementation SRASCIISymbolicKeyCodeTransformer

+ (SRASCIISymbolicKeyCodeTransformer *)sharedTransformer
{
    static SRASCIISymbolicKeyCodeTransformer *Transformer = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        Transformer = [SRASCIISymbolicKeyCodeTransformer new];
    });
    return Transformer;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _translator = _SRKeyCodeASCIITranslator.shared;
    }

    return self;
}

- (NSString *)transformedValue:(NSNumber *)aValue
     withImplicitModifierFlags:(NSNumber *)anImplicitModifierFlags
         explicitModifierFlags:(NSNumber *)anExplicitModifierFlags
               layoutDirection:(NSUserInterfaceLayoutDirection)aDirection
{
    __block NSString *result = nil;
    os_activity_initiate("Key Code -> ASCII Symbol", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (![aValue isKindOfClass:NSNumber.class])
        {
            os_trace_error("#Error Invalid key code");
            return;
        }

        result = [self symbolForKeyCode:aValue.unsignedShortValue
              withImplicitModifierFlags:anImplicitModifierFlags.unsignedIntegerValue
                  explicitModifierFlags:anExplicitModifierFlags.unsignedIntegerValue
                        layoutDirection:aDirection];
    });

    return result;
}

#pragma mark NSValueTransformer

+ (BOOL)allowsReverseTransformation
{
    return YES;
}

- (NSNumber *)reverseTransformedValue:(NSString *)aValue
{
    __block NSNumber *result = nil;
    os_activity_initiate("ASCII Symbol -> Key Code", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (![aValue isKindOfClass:NSString.class] || aValue.length > 1)
        {
            os_trace_error("#Error Invalid ASCII symbol");
            return;
        }

        unichar glyph = [aValue characterAtIndex:0];

        switch (glyph)
        {
            case NSF1FunctionKey:
                result = @(SRKeyCodeF1);
                break;
            case NSF2FunctionKey:
                result = @(SRKeyCodeF2);
                break;
            case NSF3FunctionKey:
                result = @(SRKeyCodeF3);
                break;
            case NSF4FunctionKey:
                result = @(SRKeyCodeF4);
                break;
            case NSF5FunctionKey:
                result = @(SRKeyCodeF5);
                break;
            case NSF6FunctionKey:
                result = @(SRKeyCodeF6);
                break;
            case NSF7FunctionKey:
                result = @(SRKeyCodeF7);
                break;
            case NSF8FunctionKey:
                result = @(SRKeyCodeF8);
                break;
            case NSF9FunctionKey:
                result = @(SRKeyCodeF9);
                break;
            case NSF10FunctionKey:
                result = @(SRKeyCodeF10);
                break;
            case NSF11FunctionKey:
                result = @(SRKeyCodeF11);
                break;
            case NSF12FunctionKey:
                result = @(SRKeyCodeF12);
                break;
            case NSF13FunctionKey:
                result = @(SRKeyCodeF13);
                break;
            case NSF14FunctionKey:
                result = @(SRKeyCodeF14);
                break;
            case NSF15FunctionKey:
                result = @(SRKeyCodeF15);
                break;
            case NSF16FunctionKey:
                result = @(SRKeyCodeF16);
                break;
            case NSF17FunctionKey:
                result = @(SRKeyCodeF17);
                break;
            case NSF18FunctionKey:
                result = @(SRKeyCodeF18);
                break;
            case NSF19FunctionKey:
                result = @(SRKeyCodeF19);
                break;
            case NSF20FunctionKey:
                result = @(SRKeyCodeF20);
                break;
            case NSUpArrowFunctionKey:
                result = @(SRKeyCodeUpArrow);
                break;
            case NSDownArrowFunctionKey:
                result = @(SRKeyCodeDownArrow);
                break;
            case NSLeftArrowFunctionKey:
                result = @(SRKeyCodeLeftArrow);
                break;
            case NSRightArrowFunctionKey:
                result = @(SRKeyCodeRightArrow);
                break;
            case NSEndFunctionKey:
                result = @(SRKeyCodeEnd);
                break;
            case NSHelpFunctionKey:
                result = @(SRKeyCodeHelp);
                break;
            case NSHomeFunctionKey:
                result = @(SRKeyCodeHome);
                break;
            case NSPageDownFunctionKey:
                result = @(SRKeyCodePageDown);
                break;
            case NSPageUpFunctionKey:
                result = @(SRKeyCodePageUp);
                break;
            case NSBackTabCharacter:
                result = @(SRKeyCodeTab);
                break;
            case SRKeyCodeGlyphJISUnderscore:
                result = @(SRKeyCodeJISUnderscore);
                break;
            case SRKeyCodeGlyphJISComma:
                result = @(SRKeyCodeJISKeypadComma);
                break;
            case SRKeyCodeGlyphJISYen:
                result = @(SRKeyCodeJISYen);
                break;
            case SRKeyCodeGlyphANSI0:
                result = @(SRKeyCode0);
                break;
            case SRKeyCodeGlyphANSI1:
                result = @(SRKeyCode1);
                break;
            case SRKeyCodeGlyphANSI2:
                result = @(SRKeyCode2);
                break;
            case SRKeyCodeGlyphANSI3:
                result = @(SRKeyCode3);
                break;
            case SRKeyCodeGlyphANSI4:
                result = @(SRKeyCode4);
                break;
            case SRKeyCodeGlyphANSI5:
                result = @(SRKeyCode5);
                break;
            case SRKeyCodeGlyphANSI6:
                result = @(SRKeyCode6);
                break;
            case SRKeyCodeGlyphANSI7:
                result = @(SRKeyCode7);
                break;
            case SRKeyCodeGlyphANSI8:
                result = @(SRKeyCode8);
                break;
            case SRKeyCodeGlyphANSI9:
                result = @(SRKeyCode9);
                break;
            case SRKeyCodeGlyphANSIEqual:
                result = @(SRKeyCodeEqual);
                break;
            case SRKeyCodeGlyphANSIMinus:
                result = @(SRKeyCodeMinus);
                break;
            case SRKeyCodeGlyphANSISlash:
                result = @(SRKeyCodeSlash);
                break;
            case SRKeyCodeGlyphANSIPeriod:
                result = @(SRKeyCodePeriod);
                break;
            default:
                result = [(_SRKeyCodeASCIITranslator *)self->_translator keyCodeForTranslation:aValue.lowercaseString];
                break;
        }
    });

    if (!result)
        os_trace_error("#Error Invalid value for reverse transformation");

    return result;
}

@end
