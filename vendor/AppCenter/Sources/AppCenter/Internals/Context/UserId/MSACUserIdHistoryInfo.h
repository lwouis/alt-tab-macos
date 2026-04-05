// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHistoryInfo.h"

/**
 * Model class that is intended to be used to correlate userId to a crash at app relaunch.
 */
@interface MSACUserIdHistoryInfo : MSACHistoryInfo

/**
 * User Id.
 */
@property(nonatomic, copy) NSString *userId;

/**
 * Initializes a new `MSACUserIdHistoryInfo` instance.
 *
 * @param timestamp Timestamp.
 * @param userId User Id.
 */
- (instancetype)initWithTimestamp:(NSDate *)timestamp andUserId:(NSString *)userId;

@end
