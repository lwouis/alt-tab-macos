// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACKeychainUtil.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Keychain service name suffix.
 */
static NSString *const kMSACServiceSuffix = @"AppCenter";

/**
 * Utility class for Keychain.
 */
@interface MSACKeychainUtil ()

/**
 * Store a string to Keychain with the given key.
 *
 * @param string A string data to be placed in Keychain.
 * @param key A unique key for the data.
 * @param serviceName Keychain service name.
 *
 * @return YES if stored successfully, NO otherwise.
 */
+ (BOOL)storeString:(NSString *)string forKey:(NSString *)key withServiceName:(NSString *)serviceName;

/**
 * Delete a string from Keychain with the given key.
 *
 * @param key A unique key for the data.
 * @param serviceName Keychain service name.
 *
 * @return A string data that was deleted.
 */
+ (NSString *_Nullable)deleteStringForKey:(NSString *)key withServiceName:(NSString *)serviceName;

/**
 * Get a string from Keychain with the given key.
 *
 * @param key A unique key for the data.
 * @param serviceName Keychain service name.
 *
 * @return A string data if exists.
 */
+ (NSString *_Nullable)stringForKey:(NSString *)key withServiceName:(NSString *)serviceName statusCode:(OSStatus *_Nullable)statusCode;

/**
 * Deletes items that match a search query.
 *
 * @param query A dictionary that describes the search for the keychain items you want to delete.
 *
 * @return A result code for the deletion.
 */
+ (OSStatus)deleteSecItem:(NSMutableDictionary *)query;

/**
 * Adds one or more items to a keychain.
 *
 * @param attributes A dictionary that describes the item to add.
 *
 * @return A result code for the addition.
 */
+ (OSStatus)addSecItem:(NSMutableDictionary *)attributes;

/**
 * Returns one or more keychain items that match a search query, or copies attributes of specific keychain items.
 *
 * @param query A dictionary that describes the search.
 * @param result A reference to the found items.
 *
 * @return A result code for the addition.
 */
+ (OSStatus)secItemCopyMatchingQuery:(NSMutableDictionary *)query result:(CFTypeRef *__nullable CF_RETURNS_RETAINED)result;

@end

NS_ASSUME_NONNULL_END
