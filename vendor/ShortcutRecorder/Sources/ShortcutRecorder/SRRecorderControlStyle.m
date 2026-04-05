//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <os/trace.h>
#import <os/activity.h>

#import "SRRecorderControl.h"
#import "SRRecorderControlStyle.h"


NSAttributedStringKey const SRMinimalDrawableWidthAttributeName = @"SRMinimalDrawableWidthAttributeName";


SRRecorderControlStyleComponentsAppearance SRRecorderControlStyleComponentsAppearanceFromSystem(NSAppearanceName aSystemAppearanceName)
{
    static NSDictionary<NSAppearanceName, NSNumber *> *Map = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Map = @{
            NSAppearanceNameAqua: @(SRRecorderControlStyleComponentsAppearanceAqua),
            NSAppearanceNameVibrantLight: @(SRRecorderControlStyleComponentsAppearanceVibrantLight),
            NSAppearanceNameVibrantDark: @(SRRecorderControlStyleComponentsAppearanceVibrantDark)
        }.mutableCopy;

        if (@available(macOS 10.14, *))
            [(NSMutableDictionary *)Map setObject:@(SRRecorderControlStyleComponentsAppearanceDarkAqua) forKey:NSAppearanceNameDarkAqua];
    });

    NSNumber *appearance = Map[aSystemAppearanceName];


    if (@available(macOS 10.14, *))
    {
        if (!appearance)
        {
            NSAppearance *systemAppearance = [NSAppearance appearanceNamed:aSystemAppearanceName];
            aSystemAppearanceName = [systemAppearance bestMatchFromAppearancesWithNames:Map.allKeys];

            if (aSystemAppearanceName)
                appearance = Map[aSystemAppearanceName];
        }
    }

    if (appearance)
        return appearance.unsignedIntegerValue;
    else
        return SRRecorderControlStyleComponentsAppearanceUnspecified;
}


NSAppearanceName SRRecorderControlStyleComponentsAppearanceToSystem(SRRecorderControlStyleComponentsAppearance anAppearance)
{
    switch (anAppearance)
    {
        case SRRecorderControlStyleComponentsAppearanceAqua:
            return NSAppearanceNameAqua;
        case SRRecorderControlStyleComponentsAppearanceVibrantLight:
            return NSAppearanceNameVibrantLight;
        case SRRecorderControlStyleComponentsAppearanceVibrantDark:
            return NSAppearanceNameVibrantDark;
        case SRRecorderControlStyleComponentsAppearanceDarkAqua:
        {
            if (@available(macOS 10.14, *))
                return NSAppearanceNameDarkAqua;
        }
        case SRRecorderControlStyleComponentsAppearanceUnspecified:
        default:
            [NSException raise:NSInvalidArgumentException format:@"%lu cannot be represented as NSAppearanceName", anAppearance];
            __builtin_unreachable();
    }
}


SRRecorderControlStyleComponentsTint SRRecorderControlStyleComponentsTintFromSystem(NSControlTint aSystemTint)
{
    switch (aSystemTint)
    {
        case NSBlueControlTint:
            return SRRecorderControlStyleComponentsTintBlue;
        case NSGraphiteControlTint:
            return SRRecorderControlStyleComponentsTintGraphite;
        default:
            return SRRecorderControlStyleComponentsTintUnspecified;
    }
}


NSControlTint SRRecorderControlStyleComponentsTintToSystem(SRRecorderControlStyleComponentsTint aTint)
{
    switch (aTint)
    {
        case SRRecorderControlStyleComponentsTintBlue:
            return NSBlueControlTint;
            break;
        case SRRecorderControlStyleComponentsTintGraphite:
            return NSGraphiteControlTint;
        case SRRecorderControlStyleComponentsTintUnspecified:
        default:
            [NSException raise:NSInvalidArgumentException format:@"%lu cannot be represented as NSControlTint", aTint];
            __builtin_unreachable();
    }
}


SRRecorderControlStyleComponentsLayoutDirection SRRecorderControlStyleComponentsLayoutDirectionFromSystem(NSUserInterfaceLayoutDirection aSystemLayoutDirection)
{
    switch (aSystemLayoutDirection)
    {
        case NSUserInterfaceLayoutDirectionLeftToRight:
            return SRRecorderControlStyleComponentsLayoutDirectionLeftToRight;
        case NSUserInterfaceLayoutDirectionRightToLeft:
            return SRRecorderControlStyleComponentsLayoutDirectionRightToLeft;
        default:
            return SRRecorderControlStyleComponentsLayoutDirectionUnspecified;
    }
}


NSUserInterfaceLayoutDirection SRRecorderControlStyleComponentsLayoutDirectionToSystem(SRRecorderControlStyleComponentsLayoutDirection aLayoutDirection)
{
    switch (aLayoutDirection)
    {
        case SRRecorderControlStyleComponentsLayoutDirectionLeftToRight:
            return NSUserInterfaceLayoutDirectionLeftToRight;
        case SRRecorderControlStyleComponentsLayoutDirectionRightToLeft:
            return NSUserInterfaceLayoutDirectionRightToLeft;
        case SRRecorderControlStyleComponentsLayoutDirectionUnspecified:
        default:
            [NSException raise:NSInvalidArgumentException format:@"%lu cannot be represented as NSUserInterfaceLayoutDirection", aLayoutDirection];
            __builtin_unreachable();
    }
}


@implementation SRRecorderControlStyleComponents

+ (SRRecorderControlStyleComponents *)currentComponents
{
    return [self currentComponentsForView:nil];
}

+ (SRRecorderControlStyleComponents *)currentComponentsForView:(NSView *)aView
{
    NSAppearanceName effectiveSystemAppearance = nil;

    if (aView)
        effectiveSystemAppearance = aView.effectiveAppearance.name;
    else
        effectiveSystemAppearance = NSAppearance.currentAppearance.name;

    __auto_type appearance = SRRecorderControlStyleComponentsAppearanceFromSystem(effectiveSystemAppearance);
    __auto_type tint = SRRecorderControlStyleComponentsTintFromSystem(NSColor.currentControlTint);
    __auto_type accessibility = SRRecorderControlStyleComponentsAccessibilityUnspecified;

    if (NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast)
        accessibility = SRRecorderControlStyleComponentsAccessibilityHighContrast;
    else
        accessibility = SRRecorderControlStyleComponentsAccessibilityNone;

    __auto_type layoutDirection = SRRecorderControlStyleComponentsLayoutDirectionUnspecified;

    if (aView)
        layoutDirection = SRRecorderControlStyleComponentsLayoutDirectionFromSystem(aView.userInterfaceLayoutDirection);
    else
        layoutDirection = SRRecorderControlStyleComponentsLayoutDirectionFromSystem(NSApp.userInterfaceLayoutDirection);

    return [[SRRecorderControlStyleComponents alloc] initWithAppearance:appearance
                                                          accessibility:accessibility
                                                        layoutDirection:layoutDirection
                                                                   tint:tint];
}

- (instancetype)initWithAppearance:(SRRecorderControlStyleComponentsAppearance)anAppearance
                     accessibility:(SRRecorderControlStyleComponentsAccessibility)anAccessibility
                   layoutDirection:(SRRecorderControlStyleComponentsLayoutDirection)aDirection
                              tint:(SRRecorderControlStyleComponentsTint)aTint
{
    NSAssert(anAppearance >= SRRecorderControlStyleComponentsAppearanceUnspecified && anAppearance < SRRecorderControlStyleComponentsAppearanceMax,
             @"anAppearance is outside of the allowed range.");
    NSAssert(aTint >= SRRecorderControlStyleComponentsTintUnspecified && aTint < SRRecorderControlStyleComponentsTintMax,
             @"aTint is outside of the allowed range.");
    NSAssert((anAccessibility & ~SRRecorderControlStyleComponentsAccessibilityMask) == 0,
             @"anAccessibility is outside of the allowed range.");
    NSAssert(anAccessibility == SRRecorderControlStyleComponentsAccessibilityNone ||
             (anAccessibility & SRRecorderControlStyleComponentsAccessibilityNone) == 0, @"None cannot be combined with other accessibility options.");
    NSAssert(aDirection >= SRRecorderControlStyleComponentsLayoutDirectionUnspecified && aTint < SRRecorderControlStyleComponentsLayoutDirectionMax,
             @"aDirection is outside of the allowed range.");

    self = [super init];

    if (self)
    {
        _appearance = anAppearance;
        _accessibility = anAccessibility;
        _layoutDirection = aDirection;
        _tint = aTint;
    }

    return self;
}

- (instancetype)init
{
    return [self initWithAppearance:SRRecorderControlStyleComponentsAppearanceUnspecified
                      accessibility:SRRecorderControlStyleComponentsAccessibilityUnspecified
                    layoutDirection:SRRecorderControlStyleComponentsLayoutDirectionUnspecified
                               tint:SRRecorderControlStyleComponentsTintUnspecified];
}

#pragma mark Properties

- (BOOL)isSpecified
{
    return _appearance != SRRecorderControlStyleComponentsAppearanceUnspecified &&
        _accessibility != SRRecorderControlStyleComponentsAccessibilityUnspecified &&
        _layoutDirection != SRRecorderControlStyleComponentsLayoutDirectionUnspecified &&
        _tint != SRRecorderControlStyleComponentsTintUnspecified;
}

- (NSString *)stringRepresentation
{
    NSString *appearance = nil;
    NSString *tint = nil;
    NSString *acc = nil;
    NSString *direction = nil;

    switch (self.appearance)
    {
        case SRRecorderControlStyleComponentsAppearanceDarkAqua:
            appearance = @"-darkaqua";
            break;
        case SRRecorderControlStyleComponentsAppearanceAqua:
            appearance = @"-aqua";
            break;
        case SRRecorderControlStyleComponentsAppearanceVibrantDark:
            appearance = @"-vibrantdark";
            break;
        case SRRecorderControlStyleComponentsAppearanceVibrantLight:
            appearance = @"-vibrantlight";
            break;
        case SRRecorderControlStyleComponentsAppearanceUnspecified:
            appearance = @"";
            break;

        default:
            NSAssert(NO, @"Unexpected appearance.");
            break;
    }

    switch (self.accessibility)
    {
        case SRRecorderControlStyleComponentsAccessibilityHighContrast:
            acc = @"-acc";
            break;
        case SRRecorderControlStyleComponentsAccessibilityNone:
        case SRRecorderControlStyleComponentsAccessibilityUnspecified:
            acc = @"";
            break;

        default:
            NSAssert(NO, @"Unexpected appearance.");
            break;
    }

    switch (self.layoutDirection)
    {
        case SRRecorderControlStyleComponentsLayoutDirectionLeftToRight:
            direction = @"-ltr";
            break;
        case SRRecorderControlStyleComponentsLayoutDirectionRightToLeft:
            direction = @"-rtl";
            break;
        case SRRecorderControlStyleComponentsLayoutDirectionUnspecified:
            direction = @"";
            break;

        default:
            NSAssert(NO, @"Unexpected appearance.");
            break;
    }

    switch (self.tint)
    {
        case SRRecorderControlStyleComponentsTintBlue:
            tint = @"-blue";
            break;
        case SRRecorderControlStyleComponentsTintGraphite:
            tint = @"-graphite";
            break;
        case SRRecorderControlStyleComponentsTintUnspecified:
            tint = @"";
            break;

        default:
            NSAssert(NO, @"Unexpected appearance.");
            break;
    }

    return [NSString stringWithFormat:@"%@%@%@%@", appearance, acc, direction, tint];
}

#pragma mark Methods

- (BOOL)isEqualToComponents:(SRRecorderControlStyleComponents *)anObject
{
    if (anObject == self)
        return YES;
    else if (![anObject isKindOfClass:SRRecorderControlStyleComponents.class])
        return NO;
    else
        return self.appearance == anObject.appearance &&
            self.accessibility == anObject.accessibility &&
            self.layoutDirection == anObject.layoutDirection &&
            self.tint == anObject.tint;
}

- (NSComparisonResult)compare:(SRRecorderControlStyleComponents *)anOtherComponents
         relativeToComponents:(SRRecorderControlStyleComponents *)anIdealComponents
{
    static NSDictionary<NSNumber *, NSArray<NSNumber *> *> *AppearanceOrderMap = nil;
    static NSDictionary<NSNumber *, NSArray<NSNumber *> *> *TintOrderMap = nil;
    static NSDictionary<NSNumber *, NSArray<NSNumber *> *> *DirectionOrderMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        AppearanceOrderMap = @{
            @(SRRecorderControlStyleComponentsAppearanceAqua): @[@(SRRecorderControlStyleComponentsAppearanceAqua),
                                                       @(SRRecorderControlStyleComponentsAppearanceVibrantLight),
                                                       @(SRRecorderControlStyleComponentsAppearanceDarkAqua),
                                                       @(SRRecorderControlStyleComponentsAppearanceVibrantDark),
                                                       @(SRRecorderControlStyleComponentsAppearanceUnspecified)],
            @(SRRecorderControlStyleComponentsAppearanceDarkAqua): @[@(SRRecorderControlStyleComponentsAppearanceDarkAqua),
                                                           @(SRRecorderControlStyleComponentsAppearanceVibrantDark),
                                                           @(SRRecorderControlStyleComponentsAppearanceAqua),
                                                           @(SRRecorderControlStyleComponentsAppearanceVibrantLight),
                                                           @(SRRecorderControlStyleComponentsAppearanceUnspecified)],
            @(SRRecorderControlStyleComponentsAppearanceVibrantLight): @[@(SRRecorderControlStyleComponentsAppearanceVibrantLight),
                                                               @(SRRecorderControlStyleComponentsAppearanceAqua),
                                                               @(SRRecorderControlStyleComponentsAppearanceVibrantDark),
                                                               @(SRRecorderControlStyleComponentsAppearanceDarkAqua),
                                                               @(SRRecorderControlStyleComponentsAppearanceUnspecified)],
            @(SRRecorderControlStyleComponentsAppearanceVibrantDark): @[@(SRRecorderControlStyleComponentsAppearanceVibrantDark),
                                                              @(SRRecorderControlStyleComponentsAppearanceDarkAqua),
                                                              @(SRRecorderControlStyleComponentsAppearanceVibrantLight),
                                                              @(SRRecorderControlStyleComponentsAppearanceAqua),
                                                              @(SRRecorderControlStyleComponentsAppearanceUnspecified)]
        };

        TintOrderMap = @{
            @(SRRecorderControlStyleComponentsTintBlue): @[@(SRRecorderControlStyleComponentsTintBlue),
                                                 @(SRRecorderControlStyleComponentsTintGraphite),
                                                 @(SRRecorderControlStyleComponentsTintUnspecified)],
            @(SRRecorderControlStyleComponentsTintGraphite): @[@(SRRecorderControlStyleComponentsTintGraphite),
                                                     @(SRRecorderControlStyleComponentsTintBlue),
                                                     @(SRRecorderControlStyleComponentsTintUnspecified)]
        };

        DirectionOrderMap = @{
            @(SRRecorderControlStyleComponentsLayoutDirectionLeftToRight): @[@(SRRecorderControlStyleComponentsLayoutDirectionLeftToRight),
                                                                             @(SRRecorderControlStyleComponentsLayoutDirectionRightToLeft)],
            @(SRRecorderControlStyleComponentsLayoutDirectionRightToLeft): @[@(SRRecorderControlStyleComponentsLayoutDirectionRightToLeft),
                                                                             @(SRRecorderControlStyleComponentsLayoutDirectionLeftToRight)]
        };
    });

    __auto_type CompareEnum = ^(NSUInteger a, NSUInteger b, NSArray<NSNumber *> *order) {
        NSUInteger aIndex = [order indexOfObject:@(a)];
        NSUInteger bIndex = [order indexOfObject:@(b)];

        if (aIndex < bIndex)
            return NSOrderedAscending;
        else if (aIndex > bIndex)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    };

    __auto_type CompareOptions = ^(NSUInteger a, NSUInteger b, NSUInteger ideal) {
        // How many bits match.
        int aSimilarity = __builtin_popcountl(a & ideal);
        int bSimilarity = __builtin_popcountl(b & ideal);

        // How many bits mismatch.
        int aDissimilarity = __builtin_popcountl(a & ~ideal);
        int bDissimilarity = __builtin_popcountl(b & ~ideal);

        if (aSimilarity > bSimilarity)
            return NSOrderedAscending;
        else if (aSimilarity < bSimilarity)
            return NSOrderedDescending;
        else if (aDissimilarity < bDissimilarity)
            return NSOrderedAscending;
        else if (aDissimilarity > bDissimilarity)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    };

    if (self.appearance != anOtherComponents.appearance)
        return CompareEnum(self.appearance,
                           anOtherComponents.appearance,
                           AppearanceOrderMap[@(anIdealComponents.appearance)]);
    else if (self.accessibility != anOtherComponents.accessibility)
        return CompareOptions(self.accessibility,
                              anOtherComponents.accessibility,
                              anIdealComponents.accessibility);
    else if (self.layoutDirection != anOtherComponents.layoutDirection)
        return CompareEnum(self.layoutDirection,
                           anOtherComponents.layoutDirection,
                           AppearanceOrderMap[@(anIdealComponents.layoutDirection)]);
    else if (self.tint != anOtherComponents.tint)
        return CompareEnum(self.tint,
                           anOtherComponents.tint,
                           AppearanceOrderMap[@(anIdealComponents.tint)]);
    else
        return NSOrderedSame;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)aZone
{
    return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(SRRecorderControlStyleComponents *)anObject
{
    return [self SR_isEqual:anObject
              usingSelector:@selector(isEqualToComponents:)
           ofCommonAncestor:SRRecorderControlStyleComponents.class];
}

- (NSUInteger)hash
{
    int tintBitSize = sizeof(NSUInteger) * CHAR_BIT - __builtin_clzl(SRRecorderControlStyleComponentsTintMax);
    int layoutDirectionBitSize = sizeof(NSUInteger) * CHAR_BIT - __builtin_clzl(SRRecorderControlStyleComponentsLayoutDirectionMax);
    int appearanceBitSize = sizeof(NSUInteger) * CHAR_BIT - __builtin_clzl(SRRecorderControlStyleComponentsAppearanceMax);
    return self.tint |
        (self.layoutDirection << tintBitSize) |
        (self.appearance << (tintBitSize + layoutDirectionBitSize)) |
        (self.accessibility << (tintBitSize + layoutDirectionBitSize + appearanceBitSize));
}

- (NSString *)description
{
    return [self stringRepresentation];
}

@end


@interface _SRRecorderControlStyleResourceLoaderCacheLookupPrefixesKey: NSObject <NSCopying>
@property NSString *identifier;
@property SRRecorderControlStyleComponents *components;
@end


@implementation _SRRecorderControlStyleResourceLoaderCacheLookupPrefixesKey

- (NSUInteger)hash
{
    return (self.components.hash << 32) ^ self.identifier.hash;
}

- (BOOL)isEqual:(_SRRecorderControlStyleResourceLoaderCacheLookupPrefixesKey *)anObject
{
    if (![anObject isKindOfClass:self.class])
        return NO;

    return [self.identifier isEqual:anObject.identifier] && [self.components isEqual:anObject.components];
}

- (id)copyWithZone:(NSZone *)aZone
{
    return self;
}

@end


@interface _SRRecorderControlStyleResourceLoaderCacheImageKey: NSObject <NSCopying>
@property NSString *identifier;
@property SRRecorderControlStyleComponents *components;
@property NSString *name;
@end


@implementation _SRRecorderControlStyleResourceLoaderCacheImageKey

- (NSUInteger)hash
{
    return (self.components.hash << 32) ^ (self.name.hash << 32) ^ self.components.hash;
}

- (BOOL)isEqual:(_SRRecorderControlStyleResourceLoaderCacheImageKey *)anObject
{
    if (![anObject isKindOfClass:self.class])
        return NO;

    return [self.identifier isEqual:anObject.identifier] &&
        [self.components isEqual:anObject.components] &&
        [self.name isEqual:anObject];
}

- (id)copyWithZone:(NSZone *)aZone
{
    return self;
}

@end


@implementation SRRecorderControlStyleResourceLoader
{
    NSCache *_cache;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _cache = [NSCache new];
        _cache.name = @"SRRecorderControlStyleResourceLoader";
    }

    return self;
}

- (NSDictionary<NSString *, id> *)infoForStyle:(SRRecorderControlStyle *)aStyle
{
    typedef id (^Transformer)(id anObject, NSString *aKey);
    typedef void (^Verifier)(id anObject, NSString *aKey);

    __auto_type VerifyIsType = ^(NSObject *anObject, NSString *aKey, Class aType) {
        if (![anObject isKindOfClass:aType])
            [NSException raise:NSInternalInconsistencyException
                        format:@"%@: expected %@ but got %@", aKey, NSStringFromClass(aType), NSStringFromClass(anObject.class)];
    };

    __auto_type VerifyNumberInInterval = ^(NSNumber *anObject, NSString *aKey, NSNumber *aMin, NSNumber *aMax) {
        VerifyIsType(anObject, aKey, NSNumber.class);

        if ([anObject compare:aMax] != NSOrderedAscending)
            [NSException raise:NSInternalInconsistencyException format:@"%@: value >= %@", aKey, aMax];

        if ([anObject compare:aMin] == NSOrderedAscending)
            [NSException raise:NSInternalInconsistencyException format:@"%@: value < %@", aKey, aMin];
    };

    __auto_type VerifyNumberWithMask = ^(NSNumber *anObject, NSString *aKey, NSUInteger aMask) {
        if (!anObject)
            return;

        VerifyIsType(anObject, aKey, NSNumber.class);

        if ((anObject.unsignedIntegerValue & ~aMask) != 0)
            [NSException raise:NSInternalInconsistencyException format:@"%@: value must be with mask %lu", aKey, aMask];
    };

    __auto_type VerifyDictionaryHasKey = ^(NSDictionary *anObject, NSString *aKey, NSString *aSubKey) {
        if (!anObject[aSubKey])
            [NSException raise:NSInternalInconsistencyException format:@"%@: missing %@", aKey, aSubKey];
    };

    Verifier VerifyIsArray = ^(NSArray *anObject, NSString *aKey) {
        VerifyIsType(anObject, aKey, NSArray.class);
    };

    Verifier VerifyIsDictionary = ^(NSDictionary *anObject, NSString *aKey) {
        VerifyIsType(anObject, aKey, NSDictionary.class);
    };

    Verifier VerifyIsNumber = ^(NSNumber *anObject, NSString *aKey) {
        VerifyIsType(anObject, aKey, NSNumber.class);
    };

    Verifier VerifyIsString = ^(NSString *anObject, NSString *aKey) {
        VerifyIsType(anObject, aKey, NSString.class);
    };

    Verifier VerifyIsComponents = ^(NSDictionary *anObject, NSString *aKey) {
        VerifyIsDictionary(anObject, aKey);

        if (anObject[@"appearance"])
            VerifyNumberInInterval(anObject[@"appearance"],
                                   [NSString stringWithFormat:@"%@.appearance", aKey],
                                   @(SRRecorderControlStyleComponentsAppearanceUnspecified),
                                   @(SRRecorderControlStyleComponentsAppearanceMax));

        if (anObject[@"accessibility"])
            VerifyNumberWithMask(anObject[@"accessibility"],
                                 [NSString stringWithFormat:@"%@.accessibility", aKey],
                                 SRRecorderControlStyleComponentsAccessibilityMask);

        if (anObject[@"layoutDirection"])
            VerifyNumberInInterval(anObject[@"layoutDirection"],
                                   [NSString stringWithFormat:@"%@.layoutDirection", aKey],
                                   @(SRRecorderControlStyleComponentsLayoutDirectionUnspecified),
                                   @(SRRecorderControlStyleComponentsLayoutDirectionMax));

        if (anObject[@"tint"])
            VerifyNumberInInterval(anObject[@"tint"],
                                   [NSString stringWithFormat:@"%@.tint", aKey],
                                   @(SRRecorderControlStyleComponentsTintUnspecified),
                                   @(SRRecorderControlStyleComponentsTintMax));
    };

    Verifier VerifyIsSize = ^(NSDictionary *anObject, NSString *aKey) {
        VerifyIsDictionary(anObject, aKey);

        if (anObject.count != 2)
            [NSException raise:NSInternalInconsistencyException format:@"%@: unexpected keys", aKey];

        VerifyDictionaryHasKey(anObject, aKey, @"width");
        VerifyIsNumber(anObject[@"width"], [NSString stringWithFormat:@"%@.width", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"height");
        VerifyIsNumber(anObject[@"height"], [NSString stringWithFormat:@"%@.height", aKey]);
    };

    Verifier VerifyIsEdgeInsets = ^(NSDictionary *anObject, NSString *aKey) {
        VerifyIsDictionary(anObject, aKey);

        if (anObject.count != 4)
            [NSException raise:NSInternalInconsistencyException format:@"%@: unexpected keys", aKey];

        VerifyDictionaryHasKey(anObject, aKey, @"top");
        VerifyIsNumber(anObject[@"top"], [NSString stringWithFormat:@"%@.top", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"left");
        VerifyIsNumber(anObject[@"left"], [NSString stringWithFormat:@"%@.left", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"bottom");
        VerifyIsNumber(anObject[@"bottom"], [NSString stringWithFormat:@"%@.bottom", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"right");
        VerifyIsNumber(anObject[@"right"], [NSString stringWithFormat:@"%@.right", aKey]);
    };

    Verifier VerifyIsLabelAttributes = ^(NSDictionary *anObject, NSString *aKey) {
        VerifyIsDictionary(anObject, aKey);

        if (anObject.count != 4)
            [NSException raise:NSInternalInconsistencyException format:@"%@: unexpected keys", aKey];

        VerifyDictionaryHasKey(anObject, aKey, @"fontName");
        VerifyIsString(anObject[@"fontName"], [NSString stringWithFormat:@"%@.fontName", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"fontSize");
        VerifyIsNumber(anObject[@"fontSize"], [NSString stringWithFormat:@"%@.fontSize", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"fontColorCatalogName");
        VerifyIsString(anObject[@"fontColorCatalogName"], [NSString stringWithFormat:@"%@.fontColorCatalogName", aKey]);

        VerifyDictionaryHasKey(anObject, aKey, @"fontColorName");
        VerifyIsString(anObject[@"fontColorName"], [NSString stringWithFormat:@"%@.fontColorName", aKey]);
    };

    Transformer TransformComponents = ^(NSDictionary<NSString *, NSNumber *> *anObject, NSString *aKey) {
        return [[SRRecorderControlStyleComponents alloc] initWithAppearance:anObject[@"appearance"].unsignedIntegerValue
                                                              accessibility:anObject[@"accessibility"].unsignedIntegerValue
                                                            layoutDirection:anObject[@"layoutDirection"].unsignedIntegerValue
                                                                       tint:anObject[@"tint"].unsignedIntegerValue];
    };

    Transformer TransformSize = ^(NSDictionary<NSString *, NSNumber *> *anObject, NSString *aKey) {
        return [NSValue valueWithSize:NSMakeSize(anObject[@"width"].doubleValue, anObject[@"height"].doubleValue)];
    };

    Transformer TransformEdgeInsets = ^(NSDictionary<NSString *, NSNumber *> *anObject, NSString *aKey) {
        return [NSValue valueWithEdgeInsets:NSEdgeInsetsMake(anObject[@"top"].doubleValue,
                                                             anObject[@"left"].doubleValue,
                                                             anObject[@"bottom"].doubleValue,
                                                             anObject[@"right"].doubleValue)];
    };

    Transformer TransformLabelAttributes = ^(NSDictionary<NSAttributedStringKey, id> *anObject, NSString *aKey) {
        NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
        p.alignment = NSTextAlignmentCenter;
        p.lineBreakMode = NSLineBreakByTruncatingMiddle;

        NSString *fontName = anObject[@"fontName"];
        CGFloat fontSize = [anObject[@"fontSize"] doubleValue];
        NSFont *font = [fontName isEqual:@".AppleSystemUIFont"] ? [NSFont systemFontOfSize:fontSize] : [NSFont fontWithName:fontName size:fontSize];

        NSColor *fontColor = [NSColor colorWithCatalogName:anObject[@"fontColorCatalogName"] colorName:anObject[@"fontColorName"]];

        NSMutableDictionary *attributes = @{
            NSParagraphStyleAttributeName: [p copy],
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: fontColor
        }.mutableCopy;
        attributes[SRMinimalDrawableWidthAttributeName] = @([@"…" sizeWithAttributes:attributes].width);

        return [attributes copy];
    };

    __auto_type Get = ^(NSDictionary *aSource, NSString *aKey, Verifier aVerifier, Transformer aTransformer) {
        id value = aSource[aKey];

        if (aVerifier)
            aVerifier(value, aKey);

        if (aTransformer)
            value = aTransformer(value, aKey);

        return value;
    };

    __auto_type Set = ^(NSMutableDictionary *aDestination, NSDictionary *aSource, NSString *aKey, Verifier aVerifier, Transformer aTransformer) {
        aDestination[aKey] = Get(aSource, aKey, aVerifier, aTransformer);
    };

    __block NSDictionary *info = nil;
    os_activity_initiate("-[SRRecorderControlStyleResourceLoader infoForStyle:]", OS_ACTIVITY_FLAG_DEFAULT, (^{
        os_trace_debug_with_payload("Fetching info", ^(xpc_object_t d) {
            xpc_dictionary_set_string(d, "identifier", aStyle.identifier.UTF8String);
        });

        @synchronized (self)
        {
            info = [self->_cache objectForKey:aStyle.identifier];

            if (!info)
            {
                os_trace_debug("Info is not in cache");
                NSString *resourceName = [NSString stringWithFormat:@"%@-info", aStyle.identifier];
                NSData *data = [[NSDataAsset alloc] initWithName:resourceName bundle:SRBundle()].data;

                if (!data)
                    data = [[NSDataAsset alloc] initWithName:resourceName bundle:SRBundle()].data;

                if (!data)
                    [NSException raise:NSInternalInconsistencyException format:@"Missing %@", resourceName];

                NSError *error = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                if (!json)
                    [NSException raise:NSInternalInconsistencyException
                                format:@"%@ is an invalid JSON: %@", resourceName, error.localizedFailureReason];

                NSMutableDictionary *infoInProgress = NSMutableDictionary.dictionary;

                Set(infoInProgress, json, @"supportedComponents", VerifyIsArray, ^(NSArray *anObject, NSString *aKey) {
                    NSMutableArray *components = [NSMutableArray arrayWithCapacity:anObject.count];

                    [anObject enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        NSString *subkey = [NSString stringWithFormat:@"%@.[%lu]", aKey, idx];
                        VerifyIsComponents(obj, subkey);
                        [components addObject:TransformComponents(obj, subkey)];
                    }];

                    [components addObject:[SRRecorderControlStyleComponents new]];

                    return (NSArray *)[components copy];
                });

                Set(infoInProgress, json, @"metrics", VerifyIsDictionary, ^(NSDictionary *anObject, NSString *aKey) {
                    NSMutableDictionary *metricsInProgress = [NSMutableDictionary dictionaryWithCapacity:anObject.count];

                    Set(metricsInProgress, anObject, @"minSize", VerifyIsSize, TransformSize);
                    Set(metricsInProgress, anObject, @"labelToCancel", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"cancelToClear", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"buttonToAlignment", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"baselineFromTop", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"alignmentToLabel", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"labelToAlignment", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"baselineLayoutOffsetFromBottom", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"baselineDrawingOffsetFromBottom", VerifyIsNumber, nil);
                    Set(metricsInProgress, anObject, @"focusRingCornerRadius", VerifyIsSize, TransformSize);
                    Set(metricsInProgress, anObject, @"focusRingInsets", VerifyIsEdgeInsets, TransformEdgeInsets);
                    Set(metricsInProgress, anObject, @"alignmentInsets", VerifyIsEdgeInsets, TransformEdgeInsets);
                    Set(metricsInProgress, anObject, @"normalLabelAttributes", VerifyIsLabelAttributes, TransformLabelAttributes);
                    Set(metricsInProgress, anObject, @"recordingLabelAttributes", VerifyIsLabelAttributes, TransformLabelAttributes);
                    Set(metricsInProgress, anObject, @"disabledLabelAttributes", VerifyIsLabelAttributes, TransformLabelAttributes);

                    return (NSDictionary *)[metricsInProgress copy];
                });

                info = [infoInProgress copy];
                [self->_cache setObject:info forKey:aStyle.identifier];
            }
            else
                os_trace_debug("Info is in cache");
        }
    }));

    return info;
}

- (NSArray<NSString *> *)lookupPrefixesForStyle:(SRRecorderControlStyle *)aStyle
{
    __block NSArray *lookupPrefixes = nil;
    os_activity_initiate("-[SRRecorderControlStyleResourceLoader lookupPrefixesForStyle:]", OS_ACTIVITY_FLAG_DEFAULT, (^{
        os_trace_debug_with_payload("Fetching lookup prefixes", ^(xpc_object_t d) {
            xpc_dictionary_set_string(d, "identifier", aStyle.identifier.UTF8String);
        });

        @synchronized (self)
        {
            __auto_type key = [_SRRecorderControlStyleResourceLoaderCacheLookupPrefixesKey new];
            key.identifier = [aStyle.identifier copy];
            key.components = [aStyle.effectiveComponents copy];

            lookupPrefixes = [self->_cache objectForKey:key];

            if (!lookupPrefixes)
            {
                os_trace_debug("Lookup prefixes are not in cache");
                SRRecorderControlStyleComponents *effectiveComponents = aStyle.effectiveComponents;
                NSComparator cmp = ^NSComparisonResult(SRRecorderControlStyleComponents *a, SRRecorderControlStyleComponents *b) {
                    return [a compare:b relativeToComponents:effectiveComponents];
                };
                __auto_type supportedComponents = (NSArray<SRRecorderControlStyleComponents *> *)[self infoForStyle:aStyle][@"supportedComponents"];
                supportedComponents = [supportedComponents sortedArrayWithOptions:NSSortStable usingComparator:cmp];
                lookupPrefixes = [NSMutableArray arrayWithCapacity:supportedComponents.count];

                for (SRRecorderControlStyleComponents *c in supportedComponents)
                    [(NSMutableArray *)lookupPrefixes addObject:[NSString stringWithFormat:@"%@%@", aStyle.identifier, c.stringRepresentation]];

                lookupPrefixes = [lookupPrefixes copy];
                [self->_cache setObject:lookupPrefixes forKey:key];
            }
            else
                os_trace_debug("Lookup prefixes are in cache");
        }
    }));

    return lookupPrefixes;
}

- (NSImage *)imageNamed:(NSString *)aName forStyle:(SRRecorderControlStyle *)aStyle
{
    __block NSImage *image = nil;
    os_activity_initiate("-[SRRecorderControlStyleResourceLoader imageNamed:forStyle:]", OS_ACTIVITY_FLAG_DEFAULT, (^{
        os_trace_debug_with_payload("Fetching image name", ^(xpc_object_t d) {
            xpc_dictionary_set_string(d, "identifier", aStyle.identifier.UTF8String);
            xpc_dictionary_set_string(d, "image", aName.UTF8String);
        });

        @synchronized (self)
        {
            __auto_type key = [_SRRecorderControlStyleResourceLoaderCacheImageKey new];
            key.identifier = [aStyle.identifier copy];
            key.components = [aStyle.effectiveComponents copy];
            key.name = [aName copy];
            NSArray *imageNameCache = [self->_cache objectForKey:key];

            if (!imageNameCache)
            {
                os_trace_debug("Image name is not in cache");
                NSString *imageName = nil;
                BOOL usesSRImage = YES;

                for (NSString *p in [self lookupPrefixesForStyle:aStyle])
                {
                    imageName = [NSString stringWithFormat:@"%@-%@", p, aName];

                    image = SRImage(imageName);
                    if (image)
                    {
                        usesSRImage = YES;
                        break;
                    }

                    image = [NSImage imageNamed:imageName];
                    if (image)
                    {
                        usesSRImage = NO;
                        break;
                    }
                }

                if (!image)
                    [NSException raise:NSInternalInconsistencyException format:@"Missing image named %@", aName];

                [self->_cache setObject:@[imageName, @(usesSRImage)] forKey:key];
            }
            else
            {
                os_trace_debug("Image name is in cache");
                NSString *imageName = imageNameCache[0];
                BOOL usesSRImage = [imageNameCache[1] boolValue];

                if (usesSRImage)
                    image = SRImage(imageName);
                else
                    image = [NSImage imageNamed:imageName];
            }
        }
    }));

    return image;
}

@end


@implementation SRRecorderControlStyle
{
    NSArray<NSString *> *_currentLookupPrefixes;

    NSLayoutConstraint *_backgroundTopConstraint;
    NSLayoutConstraint *_backgroundLeftConstraint;
    NSLayoutConstraint *_backgroundBottomConstraint;
    NSLayoutConstraint *_backgroundRightConstraint;

    NSLayoutConstraint *_alignmentSuggestedWidthConstraint;
    NSLayoutConstraint *_alignmentWidthConstraint;
    NSLayoutConstraint *_alignmentHeightConstraint;
    NSLayoutConstraint *_alignmentToLabelConstraint;

    NSLayoutConstraint *_labelToAlignmentConstraint;
    NSLayoutConstraint *_labelToCancelConstraint;
    NSLayoutConstraint *_cancelToAlignmentConstraint;
    NSLayoutConstraint *_clearToAlignmentConstraint;
    NSLayoutConstraint *_cancelButtonHeightConstraint;
    NSLayoutConstraint *_cancelButtonWidthConstraint;
    NSLayoutConstraint *_clearButtonHeightConstraint;
    NSLayoutConstraint *_clearButtonWidthConstraint;
    NSLayoutConstraint *_cancelToClearConstraint;
}

- (instancetype)init
{
    return [self initWithIdentifier:nil components:nil];
}

- (instancetype)initWithIdentifier:(NSString *)anIdentifier components:(SRRecorderControlStyleComponents *)aComponents
{
    if (self = [super init])
    {
        if (anIdentifier)
            _identifier = [anIdentifier copy];
        else
        {
            if (@available(macOS 10.14, *))
                _identifier = @"sr-mojave";
            else
                _identifier = @"sr-yosemite";
        }

        if (aComponents)
            _preferredComponents = [aComponents copy];
        else
            _preferredComponents = [SRRecorderControlStyleComponents new];

        _allowsVibrancy = NO;
        _opaque = NO;
        _labelDrawingFrameOpaque = YES;
        _alwaysConstraints = @[];
        _displayingConstraints = @[];
        _recordingWithValueConstraints = @[];
        _recordingWithNoValueConstraints = @[];
        _alignmentGuide = [NSLayoutGuide new];
        _backgroundDrawingGuide = [NSLayoutGuide new];
        _labelDrawingGuide = [NSLayoutGuide new];
        _cancelButtonDrawingGuide = [NSLayoutGuide new];
        _clearButtonDrawingGuide = [NSLayoutGuide new];
        _cancelButtonLayoutGuide = [NSLayoutGuide new];
        _clearButtonLayoutGuide = [NSLayoutGuide new];
        _intrinsicContentSize = NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
        _effectiveComponents = SRRecorderControlStyleComponents.currentComponents;
    }

    return self;
}

#pragma mark Properties

+ (SRRecorderControlStyleResourceLoader *)resourceLoader
{
    static SRRecorderControlStyleResourceLoader *Loader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Loader = [SRRecorderControlStyleResourceLoader new];
    });
    return Loader;
}

#pragma mark Methods

- (void)addConstraints
{
    __auto_type strongRecorderControl = self.recorderControl;
    [strongRecorderControl addLayoutGuide:self.alignmentGuide];
    [strongRecorderControl addLayoutGuide:self.backgroundDrawingGuide];
    [strongRecorderControl addLayoutGuide:self.labelDrawingGuide];
    [strongRecorderControl addLayoutGuide:self.cancelButtonDrawingGuide];
    [strongRecorderControl addLayoutGuide:self.clearButtonDrawingGuide];
    [strongRecorderControl addLayoutGuide:self.cancelButtonLayoutGuide];
    [strongRecorderControl addLayoutGuide:self.clearButtonLayoutGuide];

    __auto_type SetConstraint = ^(NSLayoutConstraint * __strong *var, NSLayoutConstraint *value) {
        *var = value;
        return value;
    };

    __auto_type MakeConstraint = ^(NSLayoutAnchor * _Nonnull firstItem,
                                   NSLayoutAnchor * _Nullable secondItem,
                                   CGFloat constant,
                                   NSLayoutPriority priority,
                                   NSLayoutRelation relation,
                                   NSString *identifier)
    {
        NSLayoutConstraint *c = nil;

        if (secondItem)
        {
            switch (relation)
            {
                case NSLayoutRelationEqual:
                    c = [firstItem constraintEqualToAnchor:secondItem constant:constant];
                    break;
                case NSLayoutRelationGreaterThanOrEqual:
                    c = [firstItem constraintGreaterThanOrEqualToAnchor:secondItem constant:constant];
                    break;
                case NSLayoutRelationLessThanOrEqual:
                    c = [firstItem constraintLessThanOrEqualToAnchor:secondItem constant:constant];
                    break;
            }
        }
        else
        {
            NSAssert([firstItem isKindOfClass:NSLayoutDimension.class],
                     @"Only dimensional anchors allow constant constraints.");

            switch (relation)
            {
                case NSLayoutRelationEqual:
                    c = [(NSLayoutDimension *)firstItem constraintEqualToConstant:constant];
                    break;
                case NSLayoutRelationGreaterThanOrEqual:
                    c = [(NSLayoutDimension *)firstItem constraintGreaterThanOrEqualToConstant:constant];
                    break;
                case NSLayoutRelationLessThanOrEqual:
                    c = [(NSLayoutDimension *)firstItem constraintLessThanOrEqualToConstant:constant];
                    break;
            }
        }

        c.priority = priority;
        c.identifier = identifier;
        return c;
    };

    __auto_type MakeEqConstraint = ^(NSLayoutAnchor * _Nonnull firstItem, NSLayoutAnchor * _Nullable secondItem, NSString *identifier) {
        return MakeConstraint(firstItem, secondItem, 0.0, NSLayoutPriorityRequired, NSLayoutRelationEqual, identifier);
    };

    __auto_type MakeGteConstraint = ^(NSLayoutAnchor * _Nonnull firstItem, NSLayoutAnchor * _Nullable secondItem, NSString *identifier) {
        return MakeConstraint(firstItem, secondItem, 0.0, NSLayoutPriorityRequired, NSLayoutRelationGreaterThanOrEqual, identifier);
    };

    _alwaysConstraints = @[
        MakeEqConstraint(self.alignmentGuide.topAnchor,
                         strongRecorderControl.topAnchor,
                         @"SR_alignmentGuide_topToView"),
        MakeEqConstraint(self.alignmentGuide.leftAnchor,
                         strongRecorderControl.leftAnchor,
                         @"SR_alignmentGuide_leftToView"),
        MakeEqConstraint(self.alignmentGuide.rightAnchor,
                         strongRecorderControl.rightAnchor,
                         @"SR_alignmentGuide_rightToView"),
        MakeConstraint(self.alignmentGuide.bottomAnchor,
                       strongRecorderControl.bottomAnchor,
                       0.0,
                       NSLayoutPriorityDefaultHigh,
                       NSLayoutRelationEqual,
                       @"SR_alignmentGuide_bottomToView"),
        SetConstraint(&_alignmentHeightConstraint, MakeEqConstraint(self.alignmentGuide.heightAnchor,
                                                                    nil,
                                                                    @"SR_alignmentGuide_height")),
        SetConstraint(&_alignmentWidthConstraint, MakeGteConstraint(self.alignmentGuide.widthAnchor,
                                                                    nil,
                                                                    @"SR_alignmentGuide_width")),
        SetConstraint(&_alignmentSuggestedWidthConstraint, MakeConstraint(self.alignmentGuide.widthAnchor,
                                                                          nil,
                                                                          0.0,
                                                                          NSLayoutPriorityDefaultLow,
                                                                          NSLayoutRelationEqual,
                                                                          @"SR_alignmentGuide_suggestedWidth")),

        SetConstraint(&_backgroundTopConstraint, MakeEqConstraint(self.alignmentGuide.topAnchor,
                                                                  self.backgroundDrawingGuide.topAnchor,
                                                                  @"SR_backgroundDrawingGuide_topToAlignment")),
        SetConstraint(&_backgroundLeftConstraint, MakeEqConstraint(self.alignmentGuide.leftAnchor,
                                                                   self.backgroundDrawingGuide.leftAnchor,
                                                                   @"SR_backgroundDrawingGuide_leftToAlignment")),
        SetConstraint(&_backgroundBottomConstraint, MakeEqConstraint(self.backgroundDrawingGuide.bottomAnchor,
                                                                     self.alignmentGuide.bottomAnchor,
                                                                     @"SR_backgroundDrawingGuide_bottomToAlignment")),
        SetConstraint(&_backgroundRightConstraint, MakeEqConstraint(self.backgroundDrawingGuide.rightAnchor,
                                                                    self.alignmentGuide.rightAnchor,
                                                                    @"SR_backgroundDrawingGuide_rightToAlignment")),

        MakeEqConstraint(self.labelDrawingGuide.topAnchor,
                         self.alignmentGuide.topAnchor,
                         @"SR_labelDrawingGuide_topToAlignment"),
        SetConstraint(&_alignmentToLabelConstraint, MakeGteConstraint(self.labelDrawingGuide.leadingAnchor,
                                                                      self.alignmentGuide.leadingAnchor,
                                                                      @"SR_labelDrawingGuide_leadingToAlignment")),
        MakeEqConstraint(self.labelDrawingGuide.bottomAnchor,
                         self.alignmentGuide.bottomAnchor,
                         @"SR_labelDrawingGuide_bottomToAlignment"),
        MakeConstraint(self.labelDrawingGuide.centerXAnchor,
                       self.alignmentGuide.centerXAnchor,
                       0.0,
                       SRRecorderControlLabelWidthPriority - 1,
                       NSLayoutRelationEqual,
                       @"SR_labelDrawingGuide_centerXToAlignment")
    ];

    _displayingConstraints = @[
        SetConstraint(&_labelToAlignmentConstraint, MakeGteConstraint(self.alignmentGuide.trailingAnchor,
                                                                      self.labelDrawingGuide.trailingAnchor,
                                                                      @"SR_labelDrawingGuide_trailingToAlignment")),
    ];

    _recordingWithNoValueConstraints = @[
        SetConstraint(&_labelToCancelConstraint, MakeGteConstraint(self.cancelButtonDrawingGuide.leadingAnchor,
                                                                   self.labelDrawingGuide.trailingAnchor,
                                                                   @"SR_labelDrawingGuide_trailingToCancel")),

        SetConstraint(&_cancelToAlignmentConstraint, MakeEqConstraint(self.alignmentGuide.trailingAnchor,
                                                                      self.cancelButtonDrawingGuide.trailingAnchor,
                                                                      @"SR_cancelButtonDrawingGuide_trailingToAlignment")),
        MakeEqConstraint(self.cancelButtonDrawingGuide.centerYAnchor,
                         self.alignmentGuide.centerYAnchor,
                         @"SR_cancelButtonDrawingGuide_centerYAlignment"),
        SetConstraint(&_cancelButtonWidthConstraint, MakeEqConstraint(self.cancelButtonDrawingGuide.widthAnchor,
                                                                      nil,
                                                                      @"SR_cancelButtonDrawingGuide_width")),
        SetConstraint(&_cancelButtonHeightConstraint, MakeEqConstraint(self.cancelButtonDrawingGuide.heightAnchor,
                                                                       nil,
                                                                       @"SR_cancelButtonDrawingGuide_height")),

        MakeEqConstraint(self.cancelButtonLayoutGuide.topAnchor,
                         self.alignmentGuide.topAnchor,
                         @"SR_cancelButtonLayoutGuide_topToAlignment"),
        MakeEqConstraint(self.cancelButtonLayoutGuide.leadingAnchor,
                         self.cancelButtonDrawingGuide.leadingAnchor,
                         @"SR_cancelButtonLayoutGuide_leadingToDrawing"),
        MakeEqConstraint(self.cancelButtonLayoutGuide.bottomAnchor,
                         self.alignmentGuide.bottomAnchor,
                         @"SR_cancelButtonLayoutGuide_bottomToAlignment"),
        MakeEqConstraint(self.cancelButtonLayoutGuide.trailingAnchor,
                         self.alignmentGuide.trailingAnchor,
                         @"SR_cancelButtonLayoutGuide_trailingToAlignment"),
    ];

    _recordingWithValueConstraints = @[
        _labelToCancelConstraint,

        MakeEqConstraint(self.cancelButtonDrawingGuide.centerYAnchor,
                         self.alignmentGuide.centerYAnchor,
                         @"SR_cancelButtonDrawingGuide_centerYToAlignment"),
        SetConstraint(&_cancelToClearConstraint, MakeEqConstraint(self.clearButtonDrawingGuide.leadingAnchor,
                                                                  self.cancelButtonDrawingGuide.trailingAnchor,
                                                                  @"SR_cancelButtonDrawingGuide_trailingToClear")),
        _cancelButtonWidthConstraint,
        _cancelButtonHeightConstraint,

        MakeEqConstraint(self.clearButtonDrawingGuide.centerYAnchor,
                         self.alignmentGuide.centerYAnchor,
                         @"SR_clearButtonDrawingGuide_centerYToAlignment"),
        SetConstraint(&_clearToAlignmentConstraint, MakeEqConstraint(self.alignmentGuide.trailingAnchor,
                                                                     self.clearButtonDrawingGuide.trailingAnchor,
                                                                     @"SR_clearButtonDrawingGuide_trailingToAlignment")),
        SetConstraint(&_clearButtonWidthConstraint, MakeEqConstraint(self.clearButtonDrawingGuide.widthAnchor,
                                                                     nil,
                                                                     @"SR_clearButtonDrawingGuide_width")),
        SetConstraint(&_clearButtonHeightConstraint, MakeEqConstraint(self.clearButtonDrawingGuide.heightAnchor,
                                                                      nil,
                                                                      @"SR_clearButtonDrawingGuide_height")),

        MakeEqConstraint(self.cancelButtonLayoutGuide.topAnchor,
                         self.alignmentGuide.topAnchor,
                         @"SR_cancelButtonLayoutGuide_topToAlignment"),
        MakeEqConstraint(self.cancelButtonLayoutGuide.leadingAnchor,
                         self.cancelButtonDrawingGuide.leadingAnchor,
                         @"SR_cancelButtonLayoutGuide_leadingToDrawing"),
        MakeEqConstraint(self.cancelButtonLayoutGuide.bottomAnchor,
                         self.alignmentGuide.bottomAnchor,
                         @"SR_cancelButtonLayoutGuide_bottomToAlignment"),
        MakeEqConstraint(self.cancelButtonLayoutGuide.trailingAnchor,
                         self.cancelButtonDrawingGuide.trailingAnchor,
                         @"SR_cancelButtonLayoutGuide_trailingToDrawing"),

        MakeEqConstraint(self.clearButtonLayoutGuide.topAnchor,
                         self.alignmentGuide.topAnchor,
                         @"SR_clearButtonLayoutGuide_topToAlignment"),
        MakeEqConstraint(self.clearButtonLayoutGuide.leadingAnchor,
                         self.clearButtonDrawingGuide.leadingAnchor,
                         @"SR_clearButtonLayoutGuide_leadingToDrawing"),
        MakeEqConstraint(self.clearButtonLayoutGuide.bottomAnchor,
                         self.alignmentGuide.bottomAnchor,
                         @"SR_clearButtonLayoutGuide_bottomToAlignment"),
        MakeEqConstraint(self.clearButtonLayoutGuide.trailingAnchor,
                         self.alignmentGuide.trailingAnchor,
                         @"SR_clearButtonLayoutGuide_trailingToAlignment"),
    ];

    strongRecorderControl.needsUpdateConstraints = YES;
}

#pragma mark SRRecorderControlStyling
@synthesize identifier = _identifier;
@synthesize allowsVibrancy = _allowsVibrancy;
@synthesize opaque = _opaque;
@synthesize labelDrawingFrameOpaque = _labelDrawingFrameOpaque;
@synthesize normalLabelAttributes = _normalLabelAttributes;
@synthesize recordingLabelAttributes = _recordingLabelAttributes;
@synthesize disabledLabelAttributes = _disabledLabelAttributes;
@synthesize bezelNormalLeft = _bezelNormalLeft;
@synthesize bezelNormalCenter = _bezelNormalCenter;
@synthesize bezelNormalRight = _bezelNormalRight;
@synthesize bezelPressedLeft = _bezelPressedLeft;
@synthesize bezelPressedCenter = _bezelPressedCenter;
@synthesize bezelPressedRight = _bezelPressedRight;
@synthesize bezelRecordingLeft = _bezelRecordingLeft;
@synthesize bezelRecordingCenter = _bezelRecordingCenter;
@synthesize bezelRecordingRight = _bezelRecordingRight;
@synthesize bezelDisabledLeft = _bezelDisabledLeft;
@synthesize bezelDisabledCenter = _bezelDisabledCenter;
@synthesize bezelDisabledRight = _bezelDisabledRight;
@synthesize cancelButton = _cancelButton;
@synthesize cancelButtonPressed = _cancelButtonPressed;
@synthesize clearButton = _clearButton;
@synthesize clearButtonPressed = _clearButtonPressed;
@synthesize focusRingCornerRadius = _focusRingCornerRadius;
@synthesize focusRingInsets = _focusRingInsets;
@synthesize baselineLayoutOffsetFromBottom = _baselineLayoutOffsetFromBottom;
@synthesize baselineDrawingOffsetFromBottom = _baselineDrawingOffsetFromBottom;
@synthesize alignmentRectInsets = _alignmentRectInsets;
@synthesize intrinsicContentSize = _intrinsicContentSize;
@synthesize alignmentGuide = _alignmentGuide;
@synthesize backgroundDrawingGuide = _backgroundDrawingGuide;
@synthesize labelDrawingGuide = _labelDrawingGuide;
@synthesize cancelButtonDrawingGuide = _cancelButtonDrawingGuide;
@synthesize clearButtonDrawingGuide = _clearButtonDrawingGuide;
@synthesize cancelButtonLayoutGuide = _cancelButtonLayoutGuide;
@synthesize clearButtonLayoutGuide = _clearButtonLayoutGuide;
@synthesize alwaysConstraints = _alwaysConstraints;
@synthesize displayingConstraints = _displayingConstraints;
@synthesize recordingWithNoValueConstraints = _recordingWithNoValueConstraints;
@synthesize recordingWithValueConstraints = _recordingWithValueConstraints;
@synthesize preferredComponents = _preferredComponents;

- (NSString *)noValueNormalLabel
{
    return SRLoc(@"Record Shortcut");
}

- (NSString *)noValueDisableLabel
{
    return SRLoc(@"Record Shortcut");
}

- (NSString *)noValueRecordingLabel
{
    return SRLoc(@"Type shortcut");
}

- (void)prepareForRecorderControl:(SRRecorderControl *)aControl
{
    NSAssert(_recorderControl == nil, @"Style was not removed properly.");

    [self willChangeValueForKey:@"recorderControl"];
    _recorderControl = aControl;
    [self didChangeValueForKey:@"recorderControl"];

    if (!aControl)
        return;

    [self addConstraints];
    [self recorderControlAppearanceDidChange:nil];

    aControl.needsDisplay = YES;
}

- (void)prepareForRemoval
{
    __auto_type strongRecorderControl = _recorderControl;
    NSAssert(strongRecorderControl != nil, @"Style was not applied properly.");

    [strongRecorderControl removeLayoutGuide:_alignmentGuide];
    [strongRecorderControl removeLayoutGuide:_backgroundDrawingGuide];
    [strongRecorderControl removeLayoutGuide:_labelDrawingGuide];
    [strongRecorderControl removeLayoutGuide:_cancelButtonDrawingGuide];
    [strongRecorderControl removeLayoutGuide:_clearButtonDrawingGuide];
    [strongRecorderControl removeLayoutGuide:_cancelButtonLayoutGuide];
    [strongRecorderControl removeLayoutGuide:_clearButtonLayoutGuide];

    [self willChangeValueForKey:@"recorderControl"];
    strongRecorderControl = nil;
    [self didChangeValueForKey:@"recorderControl"];
}

- (void)recorderControlAppearanceDidChange:(nullable id)aReason
{
    __auto_type UpdateEffectiveComponents = ^{
        SRRecorderControlStyleComponents *newComponents = nil;

        if (self->_preferredComponents.isSpecified)
            newComponents = [self->_preferredComponents copy];
        else
        {
            SRRecorderControlStyleComponents *current = [SRRecorderControlStyleComponents currentComponentsForView:self.recorderControl];

            __auto_type appearance = self->_preferredComponents.appearance;
            if (appearance == SRRecorderControlStyleComponentsAppearanceUnspecified)
                appearance = current.appearance ? current.appearance : SRRecorderControlStyleComponentsAppearanceAqua;

            __auto_type accessibility = self->_preferredComponents.accessibility;
            if (!accessibility)
                accessibility = current.accessibility ? current.accessibility : SRRecorderControlStyleComponentsAccessibilityNone;

            __auto_type layoutDirection = self->_preferredComponents.layoutDirection;
            if (!layoutDirection)
                layoutDirection = current.layoutDirection ? current.layoutDirection : SRRecorderControlStyleComponentsLayoutDirectionLeftToRight;

            __auto_type tint = self->_preferredComponents.tint;
            if (!tint)
                tint = current.tint ? current.tint : SRRecorderControlStyleComponentsTintBlue;

            newComponents = [[SRRecorderControlStyleComponents alloc] initWithAppearance:appearance
                                                                           accessibility:accessibility
                                                                         layoutDirection:layoutDirection
                                                                                    tint:tint];
        }

        [self willChangeValueForKey:@"effectiveComponents"];
        self->_effectiveComponents = newComponents;
        [self didChangeValueForKey:@"effectiveComponents"];
    };

    UpdateEffectiveComponents();

    __auto_type newLookupPrefixes = [self.class.resourceLoader lookupPrefixesForStyle:self];
    if ([newLookupPrefixes isEqual:_currentLookupPrefixes])
        return;

    // Update image if needed using KVC for KVO notifications.
    __auto_type UpdateImage = ^(NSString *imageName, SEL propName, NSRect frame) {
        NSImage *newImage = [self.class.resourceLoader imageNamed:imageName forStyle:self];
        NSString *propNameString = NSStringFromSelector(propName);

        NSAssert(newImage != nil, @"Missing image for %@!", imageName);

        if ([newImage isEqual:[self valueForKey:propNameString]])
            return;

        [self setValue:newImage forKey:propNameString];

        if (!NSIsEmptyRect(frame))
            [self.recorderControl setNeedsDisplayInRect:frame];
    };

    __auto_type strongRecorderControl = self.recorderControl;
    NSRect controlBounds = strongRecorderControl.bounds;

    UpdateImage(@"bezel-normal-left", @selector(bezelNormalLeft), controlBounds);
    UpdateImage(@"bezel-normal-center", @selector(bezelNormalCenter), controlBounds);
    UpdateImage(@"bezel-normal-right", @selector(bezelNormalRight), controlBounds);

    UpdateImage(@"bezel-pressed-left", @selector(bezelPressedLeft), controlBounds);
    UpdateImage(@"bezel-pressed-center", @selector(bezelPressedCenter), controlBounds);
    UpdateImage(@"bezel-pressed-right", @selector(bezelPressedRight), controlBounds);

    UpdateImage(@"bezel-recording-left", @selector(bezelRecordingLeft), controlBounds);
    UpdateImage(@"bezel-recording-center", @selector(bezelRecordingCenter), controlBounds);
    UpdateImage(@"bezel-recording-right", @selector(bezelRecordingRight), controlBounds);

    UpdateImage(@"bezel-disabled-left", @selector(bezelDisabledLeft), controlBounds);
    UpdateImage(@"bezel-disabled-center", @selector(bezelDisabledCenter), controlBounds);
    UpdateImage(@"bezel-disabled-right", @selector(bezelDisabledRight), controlBounds);

    UpdateImage(@"button-cancel-normal", @selector(cancelButton), self.cancelButtonDrawingGuide.frame);
    UpdateImage(@"button-cancel-pressed", @selector(cancelButtonPressed), self.cancelButtonDrawingGuide.frame);

    UpdateImage(@"button-clear-normal", @selector(clearButton), self.clearButtonDrawingGuide.frame);
    UpdateImage(@"button-clear-pressed", @selector(clearButtonPressed), self.clearButtonDrawingGuide.frame);

    _cancelButtonWidthConstraint.constant = self.cancelButton.size.width;
    _cancelButtonHeightConstraint.constant = self.cancelButton.size.height;
    _clearButtonWidthConstraint.constant = self.clearButton.size.width;
    _clearButtonHeightConstraint.constant = self.clearButton.size.height;

    if (!_currentLookupPrefixes)
    {
        __auto_type metrics = (NSDictionary *)[self.class.resourceLoader infoForStyle:self][@"metrics"];

        _alignmentRectInsets = [metrics[@"alignmentInsets"] edgeInsetsValue];
        _focusRingCornerRadius = [metrics[@"focusRingCornerRadius"] sizeValue];
        _focusRingInsets = [metrics[@"focusRingInsets"] edgeInsetsValue];
        _baselineLayoutOffsetFromBottom = [metrics[@"baselineLayoutOffsetFromBottom"] doubleValue];
        _baselineDrawingOffsetFromBottom = [metrics[@"baselineDrawingOffsetFromBottom"] doubleValue];
        _normalLabelAttributes = metrics[@"normalLabelAttributes"];
        _recordingLabelAttributes = metrics[@"recordingLabelAttributes"];
        _disabledLabelAttributes = metrics[@"disabledLabelAttributes"];

        NSSize minSize = [metrics[@"minSize"] sizeValue];
        _alignmentWidthConstraint.constant = fdim(minSize.width, _alignmentRectInsets.left + _alignmentRectInsets.right);
        _alignmentHeightConstraint.constant = fdim(minSize.height, _alignmentRectInsets.top + _alignmentRectInsets.bottom);

        _backgroundTopConstraint.constant = _alignmentRectInsets.top;
        _backgroundLeftConstraint.constant = _alignmentRectInsets.left;
        _backgroundBottomConstraint.constant = _alignmentRectInsets.bottom;
        _backgroundRightConstraint.constant = _alignmentRectInsets.right;

        _alignmentToLabelConstraint.constant = [metrics[@"alignmentToLabel"] doubleValue];
        _labelToAlignmentConstraint.constant = [metrics[@"labelToAlignment"] doubleValue];
        _labelToCancelConstraint.constant = [metrics[@"labelToCancel"] doubleValue];
        _cancelToAlignmentConstraint.constant = [metrics[@"buttonToAlignment"] doubleValue];
        _clearToAlignmentConstraint.constant = [metrics[@"buttonToAlignment"] doubleValue];
        _cancelToClearConstraint.constant = [metrics[@"cancelToClear"] doubleValue];

        CGFloat maxExpectedLeadingLabelOffset = _alignmentToLabelConstraint.constant;

        CGFloat normalLabelWidth = ceil([self.noValueNormalLabel sizeWithAttributes:_normalLabelAttributes].width);
        CGFloat disabledLabelWidth = ceil([self.noValueDisableLabel sizeWithAttributes:_disabledLabelAttributes].width);
        CGFloat recordingLabelWidth = ceil([self.noValueRecordingLabel sizeWithAttributes:_recordingLabelAttributes].width);
        CGFloat maxExpectedLabelWidth = MAX(MAX(normalLabelWidth, disabledLabelWidth), recordingLabelWidth);

        CGFloat maxExpectedTrailingLabelOffset = MAX(_labelToAlignmentConstraint.constant,
                                                     _labelToCancelConstraint.constant +
                                                     _cancelButtonWidthConstraint.constant +
                                                     _cancelToClearConstraint.constant +
                                                     _clearButtonWidthConstraint.constant +
                                                     _clearToAlignmentConstraint.constant);

        _alignmentSuggestedWidthConstraint.constant = maxExpectedLeadingLabelOffset + maxExpectedLabelWidth + maxExpectedTrailingLabelOffset;

        _intrinsicContentSize = NSMakeSize(_alignmentSuggestedWidthConstraint.constant, _alignmentHeightConstraint.constant);

        [strongRecorderControl noteFocusRingMaskChanged];
        [strongRecorderControl invalidateIntrinsicContentSize];
        strongRecorderControl.needsDisplay = YES;
    }

    _currentLookupPrefixes = newLookupPrefixes;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)aZone
{
    return [[self.class alloc] initWithIdentifier:self.identifier components:self.preferredComponents];
}

@end
