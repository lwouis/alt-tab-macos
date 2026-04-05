// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_CUSTOM_PROPERTIES_H
#define MSAC_CUSTOM_PROPERTIES_H

#import <Foundation/Foundation.h>

/**
 * Custom properties builder.
 * Collects multiple properties to send in one log.
 */
NS_SWIFT_NAME(CustomProperties)
@interface MSACCustomProperties : NSObject

/**
 * Set the specified property value with the specified key.
 * If the properties previously contained a property for the key, the old value is replaced.
 *
 * @param key   Key with which the specified value is to be set.
 * @param value Value to be set with the specified key.
 *
 * @return This instance.
 */
- (instancetype)setString:(NSString *)value forKey:(NSString *)key NS_SWIFT_NAME(set(_:forKey:));

/**
 * Set the specified property value with the specified key.
 * If the properties previously contained a property for the key, the old value is replaced.
 *
 * @param key   Key with which the specified value is to be set.
 * @param value Value to be set with the specified key.
 *
 * @return This instance.
 */
- (instancetype)setNumber:(NSNumber *)value forKey:(NSString *)key NS_SWIFT_NAME(set(_:forKey:));

/**
 * Set the specified property value with the specified key.
 * If the properties previously contained a property for the key, the old value is replaced.
 *
 * @param key   Key with which the specified value is to be set.
 * @param value Value to be set with the specified key.
 *
 * @return This instance.
 */
- (instancetype)setBool:(BOOL)value forKey:(NSString *)key NS_SWIFT_NAME(set(_:forKey:));

/**
 * Set the specified property value with the specified key.
 * If the properties previously contained a property for the key, the old value is replaced.
 *
 * @param key   Key with which the specified value is to be set.
 * @param value Value to be set with the specified key.
 *
 * @return This instance.
 */
- (instancetype)setDate:(NSDate *)value forKey:(NSString *)key NS_SWIFT_NAME(set(_:forKey:));

/**
 * Clear the property for the specified key.
 *
 * @param key Key whose mapping is to be cleared.
 *
 * @return This instance.
 */
- (instancetype)clearPropertyForKey:(NSString *)key NS_SWIFT_NAME(clearProperty(forKey:));

@end

#endif
