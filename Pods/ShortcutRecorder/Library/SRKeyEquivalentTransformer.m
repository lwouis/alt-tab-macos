//
//  Copyright 2012 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import "SRKeyEquivalentTransformer.h"
#import "SRKeyCodeTransformer.h"
#import "SRRecorderControl.h"


@implementation SRKeyEquivalentTransformer

#pragma mark Methods

+ (instancetype)sharedTransformer
{
    static dispatch_once_t OnceToken;
    static SRKeyEquivalentTransformer *Transformer = nil;
    dispatch_once(&OnceToken, ^{
        Transformer = [SRKeyEquivalentTransformer new];
    });
    return Transformer;
}

#pragma mark NSValueTransformer

+ (BOOL)allowsReverseTransformation
{
    return NO;
}

+ (Class)transformedValueClass
{
    return NSString.class;
}

- (NSString *)transformedValue:(NSDictionary *)aValue
{
    if (![aValue isKindOfClass:NSDictionary.class] && ![aValue isKindOfClass:SRShortcut.class])
        return nil;

    NSNumber *keyCode = aValue[SRShortcutKeyKeyCode];

    if (![keyCode isKindOfClass:NSNumber.class])
        return nil;

    NSNumber *modifierFlags = aValue[SRShortcutKeyModifierFlags];

    if (![modifierFlags isKindOfClass:NSNumber.class])
        modifierFlags = @(0);

    return [SRASCIISymbolicKeyCodeTransformer.sharedTransformer transformedValue:keyCode
                                                       withImplicitModifierFlags:nil
                                                           explicitModifierFlags:modifierFlags
                                                                 layoutDirection:NSUserInterfaceLayoutDirectionLeftToRight];
}

@end
