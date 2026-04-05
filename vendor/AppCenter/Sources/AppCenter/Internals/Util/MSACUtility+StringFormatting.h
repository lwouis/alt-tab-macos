// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACUtility.h"

NS_ASSUME_NONNULL_BEGIN

/*
 * Workaround for exporting symbols from category object files.
 */
extern NSString *MSACUtilityStringFormattingCategory;

/**
 * Utility class that is used throughout the SDK.
 * StringFormatting part.
 */
@interface MSACUtility (StringFormatting)

/**
 * Create SHA256 of a string.
 *
 * @param string A string.
 *
 * @returns The SHA256 of given string.
 */
+ (NSString *)sha256:(NSString *)string;

/**
 * Extract app secret from a string.
 *
 * @param string A string.
 *
 * @returns The app secret or nil if none was found.
 */
+ (NSString *)appSecretFrom:(nullable NSString *)string;

/**
 * Extract transmission target token from a string.
 *
 * @param string A string.
 *
 * @returns The tenant id or nil if none was found.
 */
+ (NSString *)transmissionTargetTokenFrom:(nullable NSString *)string;

/**
 * Extract iKey from a transmission target token string.
 *
 * @param token The transmission target token as a string.
 *
 * @returns The iKey or nil if none was found.
 */
+ (nullable NSString *)iKeyFromTargetToken:(nullable NSString *)token;

/**
 * Extract target key from a transmission target token string.
 *
 * @param token The transmission target token as a string.
 *
 * @returns The target key or nil if none was found.
 */
+ (nullable NSString *)targetKeyFromTargetToken:(NSString *)token;

/**
 * Pretty print json data payload.
 *
 * @param data A data payload.
 *
 * @returns The pretty printed json data payload.
 */
+ (nullable NSString *)prettyPrintJson:(nullable NSData *)data;

/**
 * Hide sensitive values included in string.
 *
 * @param unObfuscatedString String to obfuscate.
 * @param pattern Pattern to search for.
 * @param aTemplate Template applied to any found pattern.
 *
 * @return Obfuscated string or nil if obfuscation failed.
 */
+ (nullable NSString *)obfuscateString:(nullable NSString *)unObfuscatedString
                   searchingForPattern:(NSString *)pattern
                 toReplaceWithTemplate:(NSString *)aTemplate;

@end

NS_ASSUME_NONNULL_END
