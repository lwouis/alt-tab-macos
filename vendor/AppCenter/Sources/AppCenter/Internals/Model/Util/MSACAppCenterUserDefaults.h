// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#define MSACPrefixKeyFrom(_key) [[MSACUserDefaultsPrefixKey alloc] initWithPrefix:_key]

NS_ASSUME_NONNULL_BEGIN

/**
 * Persistent settings, a wrapper around NSUserDefaults capable of updating object or dictionary (including expiration).
 */
@interface MSACAppCenterUserDefaults : NSObject

/**
 * @return the shared settings.
 */
+ (instancetype)shared;

/**
 * Get an object in the settings, returning object if key was found, nil otherwise.
 *
 * @param key a unique key to identify the value.
 */
- (nullable id)objectForKey:(NSString *)key;

/**
 * Sets the value of the specified key in the settings.
 *
 * @param value the object to set.
 * @param key a unique key to identify the value.
 */
- (void)setObject:(id)value forKey:(NSString *)key;

/**
 * Removes a value from the settings.
 *
 * @param key the key to remove.
 */
- (void)removeObjectForKey:(NSString *)key;

/**
 * Migrates values for the old keys to new keys.
 * @param migratedKeys a dictionary for keys that contains new key as a key of dictionary and old key as a value.
 * @param service service name.
 */
- (void)migrateKeys:(NSDictionary *)migratedKeys forService:(NSString *)service;

@end

#pragma mark - Prefix key

/**
 * A class defining that the instance of this class needs wildcard migration.
 * This means that for instances of this class, MSACAppCenterUserDefautls will
 * search for the old keys starting with this key and migrate all of them.
 */
@interface MSACUserDefaultsPrefixKey : NSObject <NSCopying>

@property(nonatomic) NSString *keyPrefix;

- (instancetype)initWithPrefix:(NSString *)prefix;

@end

NS_ASSUME_NONNULL_END
