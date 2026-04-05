// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@interface MSACHistoryInfo : NSObject <NSCoding>

/**
 * Timestamp.
 */
@property(nonatomic) NSDate *timestamp;

/**
 * Initializes a new `MSACHistoryInfo` instance.
 *
 * @param timestamp Timestamp
 */
- (instancetype)initWithTimestamp:(NSDate *)timestamp;

@end
