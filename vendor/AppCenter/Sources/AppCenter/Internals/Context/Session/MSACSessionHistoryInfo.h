// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHistoryInfo.h"

/**
 * Model class that is intended to be used to correlate sessionId to a crash at app relaunch.
 */
@interface MSACSessionHistoryInfo : MSACHistoryInfo

/**
 * Session Id.
 */
@property(nonatomic, copy) NSString *sessionId;

/**
 * Initializes a new `MSACSessionHistoryInfo` instance.
 *
 * @param timestamp Timestamp.
 * @param sessionId Session Id.
 */
- (instancetype)initWithTimestamp:(NSDate *)timestamp andSessionId:(NSString *)sessionId;

@end
