// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACUserIdHistoryInfo.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MSACUserIdContextDelegate;

@interface MSACUserIdContext : NSObject

/**
 * The current userId info.
 */
@property(nonatomic) MSACUserIdHistoryInfo *currentUserIdInfo;

/**
 * The user Id history that contains user Id and timestamp as an item.
 */
@property(nonatomic) NSMutableArray<MSACUserIdHistoryInfo *> *userIdHistory;

/**
 * Hash table containing all the delegates as weak references.
 */
@property(nonatomic) NSHashTable<id<MSACUserIdContextDelegate>> *delegates;

/**
 * Get singleton instance.
 */
+ (instancetype)sharedInstance;

/**
 * Add a delegate. This method is thread safe.
 *
 * @param delegate A delegate.
 */
- (void)addDelegate:(id<MSACUserIdContextDelegate>)delegate;

/**
 * Remove a delegate. This method is thread safe.
 *
 * @param delegate A delegate.
 */
- (void)removeDelegate:(id<MSACUserIdContextDelegate>)delegate;

/**
 * Set current user Id.
 *
 * @param userId The user Id.
 */
- (void)setUserId:(nullable NSString *)userId;

/**
 * Get current user Id.
 *
 * @return The current user Id.
 */
- (NSString *)userId;

/**
 * Get user Id at specific time.
 *
 * @param date The timestamp for the user Id.
 *
 * @return The user Id at the given time.
 */
- (nullable NSString *)userIdAt:(NSDate *)date;

/**
 * Clear all user Id history.
 */
- (void)clearUserIdHistory;

/**
 * Check if userId is valid for App Center.
 *
 * @param userId The user Id.
 *
 * @return YES if valid, NO otherwise.
 */
+ (BOOL)isUserIdValidForAppCenter:(nullable NSString *)userId;

/**
 * Check if userId is valid for One Collector.
 *
 * @param userId The user Id.
 *
 * @return YES if valid, NO otherwise.
 */
+ (BOOL)isUserIdValidForOneCollector:(nullable NSString *)userId;

/**
 * Add 'c:' prefix to userId if the userId has no prefix.
 *
 * @param userId userId.
 *
 * @return prefixed userId or null if the userId was null.
 */
+ (nullable NSString *)prefixedUserIdFromUserId:(nullable NSString *)userId;

@end

NS_ASSUME_NONNULL_END
