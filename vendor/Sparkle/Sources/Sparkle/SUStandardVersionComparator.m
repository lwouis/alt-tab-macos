//
//  SUStandardVersionComparator.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"


#include "AppKitPrevention.h"

@implementation SUStandardVersionComparator

- (instancetype)init
{
    return [super init];
}

+ (SUStandardVersionComparator *)defaultComparator
{
    static SUStandardVersionComparator *defaultComparator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaultComparator = [[SUStandardVersionComparator alloc] init];
    });
    return defaultComparator;
}

typedef NS_ENUM(NSInteger, SUCharacterType) {
    kNumberType,
    kStringType,
    kPeriodSeparatorType,
    kPunctuationSeparatorType,
    kWhitespaceSeparatorType,
    kDashType,
};

- (SUCharacterType)typeOfCharacter:(NSString *)character SPU_OBJC_DIRECT
{
    if ([character isEqualToString:@"."]) {
        return kPeriodSeparatorType;
    } else if ([character isEqualToString:@"-"]) {
        return kDashType;
    } else if ([[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[character characterAtIndex:0]]) {
        return kNumberType;
    } else if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[character characterAtIndex:0]]) {
        return kWhitespaceSeparatorType;
    } else if ([[NSCharacterSet punctuationCharacterSet] characterIsMember:[character characterAtIndex:0]]) {
        return kPunctuationSeparatorType;
    } else {
        return kStringType;
    }
}

- (BOOL)isSeparatorType:(SUCharacterType)characterType SPU_OBJC_DIRECT
{
    switch (characterType) {
        case kNumberType:
        case kStringType:
        case kDashType:
            return NO;
        case kPeriodSeparatorType:
        case kPunctuationSeparatorType:
        case kWhitespaceSeparatorType:
            return YES;
    }
}

// If type A and type B are some sort of separator, consider them to be equal
- (BOOL)isEqualCharacterTypeClassForTypeA:(SUCharacterType)typeA typeB:(SUCharacterType)typeB SPU_OBJC_DIRECT
{
    switch (typeA) {
        case kNumberType:
        case kStringType:
        case kDashType:
            return (typeA == typeB);
        case kPeriodSeparatorType:
        case kPunctuationSeparatorType:
        case kWhitespaceSeparatorType: {
            switch (typeB) {
                case kPeriodSeparatorType:
                case kPunctuationSeparatorType:
                case kWhitespaceSeparatorType:
                    return YES;
                case kNumberType:
                case kStringType:
                case kDashType:
                    return NO;
            }
        }
    }
}

- (NSMutableArray<NSString *> *)splitVersionString:(NSString *)version SPU_OBJC_DIRECT
{
    NSString *character;
    NSMutableString *s;
    NSUInteger i, n;
    SUCharacterType oldType, newType;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if ([version length] == 0) {
        // Nothing to do here
        return parts;
    }
    s = [[version substringToIndex:1] mutableCopy];
    oldType = [self typeOfCharacter:s];
    n = [version length] - 1;
    for (i = 1; i <= n; ++i) {
        character = [version substringWithRange:NSMakeRange(i, 1)];
        newType = [self typeOfCharacter:character];
        if (newType == kDashType) {
            break;
        }
        if (oldType != newType || [self isSeparatorType:oldType]) {
            // We've reached a new segment
            NSString *aPart = [[NSString alloc] initWithString:s];
            [parts addObject:aPart];
            [s setString:character];
        } else {
            // Add character to string and continue
            [s appendString:character];
        }
        oldType = newType;
    }

    // Add the last part onto the array
    [parts addObject:[NSString stringWithString:s]];
    return parts;
}

// This returns the count of number and period parts at the beginning of the version
// See -balanceVersionPartsA:partsB below
- (NSUInteger)countOfNumberAndPeriodStartingParts:(NSArray<NSString *> *)parts SPU_OBJC_DIRECT
{
    NSUInteger count = 0;
    for (NSString *part in parts) {
        SUCharacterType characterType = [self typeOfCharacter:part];
        
        if (characterType == kNumberType || characterType == kPeriodSeparatorType) {
            count++;
        } else {
            break;
        }
    }
    return count;
}

// See -balanceVersionPartsA:partsB below
- (void)addNumberAndPeriodPartsToParts:(NSMutableArray<NSString *> *)toParts toNumberAndPeriodPartsCount:(NSUInteger)toNumberAndPeriodPartsCount fromParts:(NSArray<NSString *> *)fromParts fromNumberAndPeriodPartsCount:(NSUInteger)fromNumberAndPeriodPartsCount SPU_OBJC_DIRECT
{
    NSUInteger partsCountDifference = (fromNumberAndPeriodPartsCount - toNumberAndPeriodPartsCount);
    
    for (NSUInteger insertionIndex = toNumberAndPeriodPartsCount; insertionIndex < toNumberAndPeriodPartsCount + partsCountDifference; insertionIndex++) {
        SUCharacterType typeA = [self typeOfCharacter:fromParts[insertionIndex]];
        if (typeA == kPeriodSeparatorType) {
            [toParts insertObject:@"." atIndex:insertionIndex];
        } else if (typeA == kNumberType) {
            [toParts insertObject:@"0" atIndex:insertionIndex];
        } else {
            // It should not be possible to get here
            assert(false);
        }
    }
}

// If one version starts with "1.0.0" and the other starts with "1.1" we make sure they're balanced
// such that the latter version now becomes "1.1.0". This helps ensure that versions like "1.0" and "1.0.0" are equal.
- (void)balanceVersionPartsA:(NSMutableArray<NSString *> *)partsA partsB:(NSMutableArray<NSString *> *)partsB SPU_OBJC_DIRECT
{
    NSUInteger partANumberAndPeriodPartsCount = [self countOfNumberAndPeriodStartingParts:partsA];
    NSUInteger partBNumberAndPeriodPartsCount = [self countOfNumberAndPeriodStartingParts:partsB];
    
    if (partANumberAndPeriodPartsCount > partBNumberAndPeriodPartsCount) {
        [self addNumberAndPeriodPartsToParts:partsB toNumberAndPeriodPartsCount:partBNumberAndPeriodPartsCount fromParts:partsA fromNumberAndPeriodPartsCount:partANumberAndPeriodPartsCount];
    } else if (partBNumberAndPeriodPartsCount > partANumberAndPeriodPartsCount) {
        [self addNumberAndPeriodPartsToParts:partsA toNumberAndPeriodPartsCount:partANumberAndPeriodPartsCount fromParts:partsB fromNumberAndPeriodPartsCount:partBNumberAndPeriodPartsCount];
    }
}

- (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB
{
    NSMutableArray<NSString *> *splitPartsA = [self splitVersionString:versionA];
    NSMutableArray<NSString *> *splitPartsB = [self splitVersionString:versionB];
    
    [self balanceVersionPartsA:splitPartsA partsB:splitPartsB];
    
    NSArray<NSString *> *partsA = splitPartsA;
    NSArray<NSString *> *partsB = splitPartsB;

    NSString *partA, *partB;
    NSUInteger i, n;
    long long valueA, valueB;
    SUCharacterType typeA, typeB;

    n = MIN([partsA count], [partsB count]);
    for (i = 0; i < n; ++i) {
        partA = [partsA objectAtIndex:i];
        partB = [partsB objectAtIndex:i];

        typeA = [self typeOfCharacter:partA];
        typeB = [self typeOfCharacter:partB];

        // Compare types
        if ([self isEqualCharacterTypeClassForTypeA:typeA typeB:typeB]) {
            // Same type; we can compare
            if (typeA == kNumberType) {
                valueA = [partA longLongValue];
                valueB = [partB longLongValue];
                if (valueA > valueB) {
                    return NSOrderedDescending;
                } else if (valueA < valueB) {
                    return NSOrderedAscending;
                }
            } else if (typeA == kStringType) {
                NSComparisonResult result = [partA compare:partB];
                if (result != NSOrderedSame) {
                    return result;
                }
            }
        } else {
            // Not the same type? Now we have to do some validity checking
            if (typeA != kStringType && typeB == kStringType) {
                // typeA wins
                return NSOrderedDescending;
            } else if (typeA == kStringType && typeB != kStringType) {
                // typeB wins
                return NSOrderedAscending;
            } else {
                // One is a number and the other is a period. The period is invalid
                if (typeA == kNumberType) {
                    return NSOrderedDescending;
                } else {
                    return NSOrderedAscending;
                }
            }
        }
    }
    // The versions are equal up to the point where they both still have parts
    // Lets check to see if one is larger than the other
    if ([partsA count] != [partsB count]) {
        // Yep. Lets get the next part of the larger
        // n holds the index of the part we want.
        NSString *missingPart;
        SUCharacterType missingType;
        NSComparisonResult shorterResult, largerResult;

        if ([partsA count] > [partsB count]) {
            missingPart = [partsA objectAtIndex:n];
            shorterResult = NSOrderedAscending;
            largerResult = NSOrderedDescending;
        } else {
            missingPart = [partsB objectAtIndex:n];
            shorterResult = NSOrderedDescending;
            largerResult = NSOrderedAscending;
        }

        missingType = [self typeOfCharacter:missingPart];
        // Check the type
        if (missingType == kStringType) {
            // It's a string. Shorter version wins
            return shorterResult;
        } else {
            // It's a number/period. Larger version wins
            return largerResult;
        }
    }

    // The 2 strings are identical
    return NSOrderedSame;
}


@end
