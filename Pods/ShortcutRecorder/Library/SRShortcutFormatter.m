//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import "SRShortcutFormatter.h"
#import "SRShortcut.h"
#import "SRKeyCodeTransformer.h"
#import "SRModifierFlagsTransformer.h"


@implementation SRShortcutFormatter

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _isKeyCodeLiteral = YES;
        _usesASCIICapableKeyboardInputSource = YES;
        _layoutDirection = NSApp.userInterfaceLayoutDirection;
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self)
    {
        _isKeyCodeLiteral = YES;
        _usesASCIICapableKeyboardInputSource = YES;
        _layoutDirection = NSApp.userInterfaceLayoutDirection;
    }

    return self;
}

#pragma mark NSFormatter

- (NSString *)stringForObjectValue:(SRShortcut *)aShortcut
{
    if (![aShortcut isKindOfClass:SRShortcut.class])
        return nil;

    SRKeyCodeTransformer *keyTransformer = nil;

    if (self.isKeyCodeLiteral && self.usesASCIICapableKeyboardInputSource)
        keyTransformer = SRASCIILiteralKeyCodeTransformer.sharedTransformer;
    else if (self.isKeyCodeLiteral)
        keyTransformer = SRLiteralKeyCodeTransformer.sharedTransformer;
    else if (self.usesASCIICapableKeyboardInputSource)
        keyTransformer = SRASCIISymbolicKeyCodeTransformer.sharedTransformer;
    else
        keyTransformer = SRSymbolicKeyCodeTransformer.sharedTransformer;

    SRModifierFlagsTransformer *flagsTransformer = nil;

    if (self.areModifierFlagsLiteral)
        flagsTransformer = SRLiteralModifierFlagsTransformer.sharedTransformer;
    else
        flagsTransformer = SRSymbolicModifierFlagsTransformer.sharedTransformer;

    NSString *key = [keyTransformer transformedValue:@(aShortcut.keyCode)
                           withImplicitModifierFlags:nil
                               explicitModifierFlags:@(aShortcut.modifierFlags)
                                     layoutDirection:self.layoutDirection];

    if (!key)
        key = [NSString stringWithFormat:@"<%hu>", aShortcut.keyCode];

    NSString *flags = [flagsTransformer transformedValue:@(aShortcut.modifierFlags)];

    return [NSString stringWithFormat:@"%@%@", flags, key];
}

- (BOOL)getObjectValue:(id __autoreleasing *)anObject forString:(NSString *)aString errorDescription:(NSString *__autoreleasing *)anError
{
    if (!self.isKeyCodeLiteral || !self.usesASCIICapableKeyboardInputSource || self.layoutDirection != NSUserInterfaceLayoutDirectionLeftToRight)
        return NO;

    SRShortcut *shortcut = [SRShortcut shortcutWithKeyEquivalent:aString];

    if (!shortcut)
        return NO;

    if (anObject)
        *anObject = shortcut;

    return YES;
}

@end
