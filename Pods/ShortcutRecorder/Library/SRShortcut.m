//
//  Copyright 2018 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <os/trace.h>

#import "SRCommon.h"
#import "SRKeyCodeTransformer.h"
#import "SRShortcutFormatter.h"
#import "SRModifierFlagsTransformer.h"
#import "SRKeyBindingTransformer.h"

#import "SRShortcut.h"


SRShortcutKey const SRShortcutKeyKeyCode = @"keyCode";
SRShortcutKey const SRShortcutKeyModifierFlags = @"modifierFlags";
SRShortcutKey const SRShortcutKeyCharacters = @"characters";
SRShortcutKey const SRShortcutKeyCharactersIgnoringModifiers = @"charactersIgnoringModifiers";

NSString *const SRShortcutKeyCode = SRShortcutKeyKeyCode;
NSString *const SRShortcutModifierFlagsKey = SRShortcutKeyModifierFlags;
NSString *const SRShortcutCharacters = SRShortcutKeyCharacters;
NSString *const SRShortcutCharactersIgnoringModifiers = SRShortcutKeyCharactersIgnoringModifiers;


@implementation SRShortcut

+ (instancetype)shortcutWithCode:(SRKeyCode)aKeyCode
                   modifierFlags:(NSEventModifierFlags)aModifierFlags
                      characters:(NSString *)aCharacters
     charactersIgnoringModifiers:(NSString *)aCharactersIgnoringModifiers
{
    return [[self alloc] initWithCode:aKeyCode
                        modifierFlags:aModifierFlags
                            characters:aCharacters
           charactersIgnoringModifiers:aCharactersIgnoringModifiers];
}

+ (instancetype)shortcutWithEvent:(NSEvent *)aKeyboardEvent
{
    __auto_type eventType = aKeyboardEvent.type;
    if (((1 << eventType) & (NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged)) == 0)
    {
        os_trace_error("#Error aKeyboardEvent must be either NSEventTypeKeyUp, NSEventTypeKeyDown or NSEventTypeFlagsChanged, but got %lu", aKeyboardEvent.type);
        return nil;
    }

    __auto_type keyCode = aKeyboardEvent.keyCode;
    __auto_type modifierFlags = aKeyboardEvent.modifierFlags;
    if (eventType == NSEventTypeFlagsChanged)
    {
        if (keyCode == kVK_Command || keyCode == kVK_RightCommand)
            modifierFlags |= NSEventModifierFlagCommand;
        else if (keyCode == kVK_Option || keyCode == kVK_RightOption)
            modifierFlags |= NSEventModifierFlagOption;
        else if (keyCode == kVK_Shift || keyCode == kVK_RightShift)
            modifierFlags |= NSEventModifierFlagShift;
        else if (keyCode == kVK_Control || keyCode == kVK_RightControl)
            modifierFlags |= NSEventModifierFlagControl;

        keyCode = SRKeyCodeNone;
    }

    NSString *characters = @"";
    NSString *charactersIgnoringModifiers = @"";
    if (eventType != NSEventTypeFlagsChanged)
    {
        @try
        {
            characters = aKeyboardEvent.characters;
            charactersIgnoringModifiers = aKeyboardEvent.charactersIgnoringModifiers;
        }
        @catch (NSException *e)
        {
            if (!NSThread.isMainThread)
            {
                NSParameterAssert(NO);
                os_trace_error("#Error #Developer AppKit failed to extract characters because it is used in non-main thread");
            }
            else
                @throw;
        }
    }

    return [self shortcutWithCode:keyCode
                    modifierFlags:modifierFlags
                       characters:characters
      charactersIgnoringModifiers:charactersIgnoringModifiers];
}

+ (instancetype)shortcutWithDictionary:(NSDictionary *)aDictionary
{
    NSNumber *keyCode = aDictionary[SRShortcutKeyKeyCode];
    SRKeyCode keyCodeValue = [keyCode isKindOfClass:NSNumber.class] ? keyCode.unsignedShortValue : SRKeyCodeNone;
    NSUInteger modifierFlagsValue = 0;
    NSString *charactersValue = nil;
    NSString *charactersIgnoringModifiersValue = nil;

    NSNumber *modifierFlags = aDictionary[SRShortcutKeyModifierFlags];
    if ((NSNull *)modifierFlags != NSNull.null)
        modifierFlagsValue = modifierFlags.unsignedIntegerValue;

    NSString *characters = aDictionary[SRShortcutKeyCharacters];
    if ((NSNull *)characters != NSNull.null)
        charactersValue = characters;

    NSString *charactersIgnoringModifiers = aDictionary[SRShortcutKeyCharactersIgnoringModifiers];
    if ((NSNull *)charactersIgnoringModifiers != NSNull.null)
        charactersIgnoringModifiersValue = charactersIgnoringModifiers;

    return [self shortcutWithCode:keyCodeValue
                    modifierFlags:modifierFlagsValue
                       characters:charactersValue
      charactersIgnoringModifiers:charactersIgnoringModifiersValue];
}

+ (instancetype)shortcutWithKeyEquivalent:(NSString *)aKeyEquivalent
{
    static NSCharacterSet *PossibleFlags = nil;
    static dispatch_once_t OnceToken;
    dispatch_once(&OnceToken, ^{
        PossibleFlags = [NSCharacterSet characterSetWithCharactersInString:[NSString stringWithFormat:@"%C%C%C%C",
                                                                            SRModifierFlagGlyphCommand,
                                                                            SRModifierFlagGlyphOption,
                                                                            SRModifierFlagGlyphShift,
                                                                            SRModifierFlagGlyphControl]];
    });

    NSScanner *parser = [NSScanner scannerWithString:aKeyEquivalent];
    parser.caseSensitive = NO;

    NSString *modifierFlagsString = @"";
    [parser scanCharactersFromSet:PossibleFlags intoString:&modifierFlagsString];
    NSString *keyCodeString = [aKeyEquivalent substringFromIndex:parser.scanLocation];

    if (!modifierFlagsString.length && !keyCodeString.length)
        return nil;

    NSNumber *modifierFlags = @0;
    if (modifierFlagsString.length)
        modifierFlags = [SRSymbolicModifierFlagsTransformer.sharedTransformer reverseTransformedValue:modifierFlagsString];

    NSNumber *keyCode = @(SRKeyCodeNone);
    if (keyCodeString.length)
        keyCode = [SRASCIILiteralKeyCodeTransformer.sharedTransformer reverseTransformedValue:keyCodeString];

    if (!modifierFlags || !keyCode)
        return nil;

    NSString *characters = [SRASCIISymbolicKeyCodeTransformer.sharedTransformer transformedValue:keyCode
                                                                       withImplicitModifierFlags:modifierFlags
                                                                           explicitModifierFlags:nil
                                                                                 layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
    NSString *charactersIgnoringModifiers = [SRASCIISymbolicKeyCodeTransformer.sharedTransformer transformedValue:keyCode
                                                                                        withImplicitModifierFlags:nil
                                                                                            explicitModifierFlags:modifierFlags
                                                                                                  layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
    return [self shortcutWithCode:keyCode.unsignedShortValue
                    modifierFlags:modifierFlags.unsignedIntegerValue
                       characters:characters
      charactersIgnoringModifiers:charactersIgnoringModifiers];
}

+ (nullable instancetype)shortcutWithKeyBinding:(NSString *)aKeyBinding
{
    return [SRKeyBindingTransformer.sharedTransformer transformedValue:aKeyBinding];
}

- (instancetype)initWithCode:(SRKeyCode)aKeyCode
               modifierFlags:(NSEventModifierFlags)aModifierFlags
                  characters:(NSString *)aCharacters
 charactersIgnoringModifiers:(NSString *)aCharactersIgnoringModifiers
{
    self = [super init];

    if (self)
    {
        _keyCode = aKeyCode;
        _modifierFlags = aModifierFlags & SRCocoaModifierFlagsMask;

        if (aCharacters)
            _characters = [aCharacters copy];
        else if (aKeyCode != SRKeyCodeNone)
            _characters = [SRASCIISymbolicKeyCodeTransformer.sharedTransformer transformedValue:@(aKeyCode)
                                                                      withImplicitModifierFlags:@(aModifierFlags)
                                                                          explicitModifierFlags:nil
                                                                                layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];

        if (aCharactersIgnoringModifiers)
            _charactersIgnoringModifiers = [aCharactersIgnoringModifiers copy];
        else if (aKeyCode != SRKeyCodeNone)
            _charactersIgnoringModifiers = [SRASCIISymbolicKeyCodeTransformer.sharedTransformer transformedValue:@(aKeyCode)
                                                                                       withImplicitModifierFlags:nil
                                                                                           explicitModifierFlags:@(aModifierFlags)
                                                                                                 layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
    }

    return self;
}


#pragma mark Properties

- (NSDictionary<SRShortcutKey, id> *)dictionaryRepresentation
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:4];

    d[SRShortcutKeyKeyCode] = @(self.keyCode);
    d[SRShortcutKeyModifierFlags] = @(self.modifierFlags);

    if (self.characters)
        d[SRShortcutKeyCharacters] = self.characters;

    if (self.charactersIgnoringModifiers)
        d[SRShortcutKeyCharactersIgnoringModifiers] = self.charactersIgnoringModifiers;

    return d;
}


#pragma mark Methods

- (NSString *)readableStringRepresentation:(BOOL)isASCII
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (isASCII)
        return SRReadableASCIIStringForCocoaModifierFlagsAndKeyCode(self.modifierFlags, self.keyCode);
    else
        return SRReadableStringForCocoaModifierFlagsAndKeyCode(self.modifierFlags, self.keyCode);
#pragma clang diagnostic pop
}


#pragma mark Equality

- (BOOL)isEqualToShortcut:(SRShortcut *)aShortcut
{
    if (aShortcut == self)
        return YES;
    else if (![aShortcut isKindOfClass:SRShortcut.class])
        return NO;
    else
        return (aShortcut.keyCode == self.keyCode && aShortcut.modifierFlags == self.modifierFlags);
}

- (BOOL)isEqualToDictionary:(NSDictionary<SRShortcutKey, id> *)aDictionary
{
    if ([aDictionary[SRShortcutKeyKeyCode] isKindOfClass:NSNumber.class])
        return [aDictionary[SRShortcutKeyKeyCode] unsignedShortValue] == self.keyCode && ([aDictionary[SRShortcutKeyModifierFlags] unsignedIntegerValue] & SRCocoaModifierFlagsMask) == self.modifierFlags;
    else if (!aDictionary[SRShortcutKeyKeyCode] && self.keyCode == SRKeyCodeNone)
        return ([aDictionary[SRShortcutKeyModifierFlags] unsignedIntegerValue] & SRCocoaModifierFlagsMask) == self.modifierFlags;
    else
        return NO;
}

- (BOOL)isEqualToKeyEquivalent:(nullable NSString *)aKeyEquivalent withModifierFlags:(NSEventModifierFlags)aModifierFlags
{
    if (!aKeyEquivalent.length || self.keyCode == SRKeyCodeNone)
        return NO;

    if ([self isEqualToKeyEquivalent:aKeyEquivalent
                   withModifierFlags:aModifierFlags
                    usingTransformer:SRASCIISymbolicKeyCodeTransformer.sharedTransformer])
    {
        return YES;
    }

    return [self isEqualToKeyEquivalent:aKeyEquivalent
                      withModifierFlags:aModifierFlags
                       usingTransformer:SRSymbolicKeyCodeTransformer.sharedTransformer];
}

- (BOOL)isEqualToKeyEquivalent:(NSString *)aKeyEquivalent
             withModifierFlags:(NSEventModifierFlags)aModifierFlags
              usingTransformer:(SRKeyCodeTransformer *)aTransformer
{
    if (!aKeyEquivalent.length || self.keyCode == SRKeyCodeNone)
        return NO;

    aModifierFlags &= SRCocoaModifierFlagsMask;

    // Special case: Both ⇤ and ⇥ key equivalents respond to SRKeyCodeTab.
    if (self.keyCode == SRKeyCodeTab &&
        self.modifierFlags == aModifierFlags &&
        aKeyEquivalent.length == 1 &&
        ([aKeyEquivalent characterAtIndex:0] == NSTabCharacter ||
         [aKeyEquivalent characterAtIndex:0] == NSBackTabCharacter))
    {
        return YES;
    }

    NSUserInterfaceLayoutDirection layoutDirection = NSApp.userInterfaceLayoutDirection;
    NSString *unalteredKeyEquivalent = [aTransformer transformedValue:@(self.keyCode)
                                            withImplicitModifierFlags:@(0)
                                                explicitModifierFlags:@(self.modifierFlags)
                                                      layoutDirection:layoutDirection];

    if ([unalteredKeyEquivalent isEqualToString:aKeyEquivalent] && self.modifierFlags == aModifierFlags)
        return YES;

    if ((self.modifierFlags & aModifierFlags) != aModifierFlags)
    {
        // All explicitly specified key equivalent modifier flags must appear in the key code flags.
        return NO;
    }

    static const NSEventModifierFlags PossibleFlags[] = {
        0,
        NSEventModifierFlagControl,
        NSEventModifierFlagCommand,
        NSEventModifierFlagShift,
        NSEventModifierFlagOption,
        NSEventModifierFlagControl | NSEventModifierFlagCommand,
        NSEventModifierFlagControl | NSEventModifierFlagShift,
        NSEventModifierFlagControl | NSEventModifierFlagOption,
        NSEventModifierFlagCommand | NSEventModifierFlagShift,
        NSEventModifierFlagCommand | NSEventModifierFlagOption,
        NSEventModifierFlagShift | NSEventModifierFlagOption,
        NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagShift,
        NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption,
        NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption,
        NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption
    };
    static const size_t PossibleFlagsSize = sizeof(PossibleFlags) / sizeof(NSEventModifierFlags);

    // Key equivalents may implicitly include modifier flags, including those already specified as explicit.
    // E.g. the shift-a, shift-A and A key equivalents are equal. Note that "a" is a completely different key equivalent.
    NSEventModifierFlags implicitFlags = self.modifierFlags & ~aModifierFlags;
    NSEventModifierFlags explicitFlags = aModifierFlags;

    for (size_t i = 0; i < PossibleFlagsSize; ++i)
    {
        NSEventModifierFlags flags = PossibleFlags[i];

        if ((explicitFlags & flags) != flags)
            continue;

        // Guess that the given sub-combination of explicit modifier flags is also included into
        // the key equivalent as implicit.
        NSString *alteredKeyEquivalent = [aTransformer transformedValue:@(self.keyCode)
                                              withImplicitModifierFlags:@(implicitFlags | flags)
                                                  explicitModifierFlags:@(explicitFlags)
                                                        layoutDirection:layoutDirection];

        // Implicit flags must change the appearance, otherwise they are explicit.
        if ([alteredKeyEquivalent isEqualToString:unalteredKeyEquivalent])
            continue;

        if ([alteredKeyEquivalent isEqualToString:aKeyEquivalent])
            return YES;
    }

    return NO;
}


#pragma mark Subscript

- (nullable id)objectForKeyedSubscript:(SRShortcutKey)aKey
{
    if ([aKey isEqualToString:SRShortcutKeyKeyCode])
        return @(self.keyCode);
    else if ([aKey isEqualToString:SRShortcutKeyModifierFlags])
        return @(self.modifierFlags);
    else if ([aKey isEqualToString:SRShortcutKeyCharacters])
        return self.characters;
    else if ([aKey isEqualToString:SRShortcutKeyCharactersIgnoringModifiers])
        return self.charactersIgnoringModifiers;
    else
        return nil;
}


#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)aZone
{
    // SRShortcut is immutable.
    return self;
}


#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    return [self initWithCode:[[aDecoder decodeObjectOfClass:NSNumber.class forKey:SRShortcutKeyKeyCode] unsignedShortValue]
                modifierFlags:[[aDecoder decodeObjectOfClass:NSNumber.class forKey:SRShortcutKeyModifierFlags] unsignedIntegerValue]
                   characters:[aDecoder decodeObjectOfClass:NSString.class forKey:SRShortcutKeyCharacters]
  charactersIgnoringModifiers:[aDecoder decodeObjectOfClass:NSString.class forKey:SRShortcutKeyCharactersIgnoringModifiers]];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:SRBundle().infoDictionary[(__bridge NSString *)kCFBundleVersionKey] forKey:@"version"];
    [aCoder encodeObject:@(self.keyCode) forKey:SRShortcutKeyKeyCode];
    [aCoder encodeObject:@(self.modifierFlags) forKey:SRShortcutKeyModifierFlags];
    [aCoder encodeObject:self.characters forKey:SRShortcutKeyCharacters];
    [aCoder encodeObject:self.charactersIgnoringModifiers forKey:SRShortcutKeyCharactersIgnoringModifiers];
}


#pragma mark NSObject

- (BOOL)isEqual:(NSObject *)anObject
{
    return [self SR_isEqual:anObject usingSelector:@selector(isEqualToShortcut:) ofCommonAncestor:SRShortcut.class];
}

- (NSUInteger)hash
{
    // SRCocoaModifierFlagsMask leaves enough bits for key code
    return (self.modifierFlags & SRCocoaModifierFlagsMask) | self.keyCode;
}

- (NSString *)description
{
    static SRShortcutFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [SRShortcutFormatter new];
        formatter.usesASCIICapableKeyboardInputSource = YES;
        formatter.isKeyCodeLiteral = YES;
        formatter.layoutDirection = NSUserInterfaceLayoutDirectionLeftToRight;
    });

    return [formatter stringForObjectValue:self];
}

@end


@implementation SRShortcut (Carbon)

- (UInt32)carbonKeyCode
{
    if (self.keyCode == SRKeyCodeNone)
        os_trace_error("#Critical SRKeyCodeNone has no representation in Carbon");

    return self.keyCode;
}

- (UInt32)carbonModifierFlags
{
    switch (self.carbonKeyCode)
    {
        case SRKeyCodeF1:
        case SRKeyCodeF2:
        case SRKeyCodeF3:
        case SRKeyCodeF4:
        case SRKeyCodeF5:
        case SRKeyCodeF6:
        case SRKeyCodeF7:
        case SRKeyCodeF8:
        case SRKeyCodeF9:
        case SRKeyCodeF10:
        case SRKeyCodeF11:
        case SRKeyCodeF12:
        case SRKeyCodeF13:
        case SRKeyCodeF14:
        case SRKeyCodeF15:
        case SRKeyCodeF16:
        case SRKeyCodeF17:
        case SRKeyCodeF18:
        case SRKeyCodeF19:
        case SRKeyCodeF20:
            return SRCocoaToCarbonFlags(self.modifierFlags) | NSFunctionKeyMask;
        default:
            return SRCocoaToCarbonFlags(self.modifierFlags);
    }
}

@end


NSString *SRReadableStringForCocoaModifierFlagsAndKeyCode(NSEventModifierFlags aModifierFlags, SRKeyCode aKeyCode)
{
    SRKeyCodeTransformer *t = [SRKeyCodeTransformer sharedPlainTransformer];
    NSString *c = [t transformedValue:@(aKeyCode)];

    if (!c)
        c = [NSString stringWithFormat:@"<%hu>", aKeyCode];

    return [NSString stringWithFormat:@"%@%@%@%@%@",
                                      (aModifierFlags & NSEventModifierFlagCommand ? SRLoc(@"Command-") : @""),
                                      (aModifierFlags & NSEventModifierFlagOption ? SRLoc(@"Option-") : @""),
                                      (aModifierFlags & NSEventModifierFlagControl ? SRLoc(@"Control-") : @""),
                                      (aModifierFlags & NSEventModifierFlagShift ? SRLoc(@"Shift-") : @""),
                                      c];
}


NSString *SRReadableASCIIStringForCocoaModifierFlagsAndKeyCode(NSEventModifierFlags aModifierFlags, SRKeyCode aKeyCode)
{
    SRKeyCodeTransformer *t = [SRKeyCodeTransformer sharedPlainASCIITransformer];
    NSString *c = [t transformedValue:@(aKeyCode)];

    if (!c)
        c = [NSString stringWithFormat:@"<%hu>", aKeyCode];

    return [NSString stringWithFormat:@"%@%@%@%@%@",
            (aModifierFlags & NSEventModifierFlagCommand ? SRLoc(@"Command-") : @""),
            (aModifierFlags & NSEventModifierFlagOption ? SRLoc(@"Option-") : @""),
            (aModifierFlags & NSEventModifierFlagControl ? SRLoc(@"Control-") : @""),
            (aModifierFlags & NSEventModifierFlagShift ? SRLoc(@"Shift-") : @""),
            c];
}


BOOL SRKeyCodeWithFlagsEqualToKeyEquivalentWithFlags(SRKeyCode aKeyCode,
                                                     NSEventModifierFlags aKeyCodeFlags,
                                                     NSString *aKeyEquivalent,
                                                     NSEventModifierFlags aKeyEquivalentModifierFlags)
{
    SRShortcut *s = [[SRShortcut alloc] initWithCode:aKeyCode
                                       modifierFlags:aKeyCodeFlags
                                          characters:nil
                         charactersIgnoringModifiers:nil];
    return [s isEqualToKeyEquivalent:aKeyEquivalent withModifierFlags:aKeyEquivalentModifierFlags];
}
