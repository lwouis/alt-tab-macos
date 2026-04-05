// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACSessionHistoryInfo.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSACSessionContext : NSObject

/**
 * The current session info.
 */
@property(nonatomic) MSACSessionHistoryInfo *currentSessionInfo;

/**
 * The session history that contains session Id and timestamp as an item.
 */
@property(nonatomic) NSMutableArray<MSACSessionHistoryInfo *> *sessionHistory;

/**
 * Get singleton instance.
 */
+ (instancetype)sharedInstance;

/**
 * Set current session Id.
 *
 * @param sessionId The session Id.
 */
- (void)setSessionId:(nullable NSString *)sessionId;

/**
 * Get current session Id.
 *
 * @return The current session Id.
 */
- (NSString *)sessionId;

/**
 * Get session Id at specific time.
 *
 * @param date The timestamp for the session.
 *
 * @return The session Id at the given time.
 */
- (nullable NSString *)sessionIdAt:(NSDate *)date;

/**
 * Clear all session Id history.
 *
 * @param keepCurrentSession YES to keep current session, NO to delete every entry.
 */
- (void)clearSessionHistoryAndKeepCurrentSession:(BOOL)keepCurrentSession;

@end

NS_ASSUME_NONNULL_END
