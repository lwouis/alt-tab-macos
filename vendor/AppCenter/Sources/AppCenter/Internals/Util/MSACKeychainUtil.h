// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Utility class for Keychain.
 */
@interface MSACKeychainUtil : NSObject

/**
 * Store a string to Keychain with the given key.
 *
 * @param string A string data to be placed in Keychain.
 * @param key A unique key for the data.
 *
 * @return YES if stored successfully, NO otherwise.
 */
+ (BOOL)storeString:(NSString *)string forKey:(NSString *)key;

/**
 * Delete a string from Keychain with the given key.
 *
 * @param key A unique key for the data.
 *
 * @return A string data that was deleted.
 */
+ (NSString *_Nullable)deleteStringForKey:(NSString *)key;

/**
 * Get a string from Keychain with the given key.
 *
 * @param key A unique key for the data.
 *
 * @return A string data if exists.
 */
+ (NSString *_Nullable)stringForKey:(NSString *)key statusCode:(OSStatus *_Nullable)statusCode;

/**
 * Clear all keys and strings.
 *
 * @return YES if cleared successfully, NO otherwise.
 */
+ (BOOL)clear;

@end

NS_ASSUME_NONNULL_END
