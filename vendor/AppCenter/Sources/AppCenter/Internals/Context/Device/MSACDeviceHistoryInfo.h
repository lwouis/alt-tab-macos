// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHistoryInfo.h"

@class MSACDevice;

/**
 * Model class that correlates MSACDevice to a crash at app relaunch.
 */
@interface MSACDeviceHistoryInfo : MSACHistoryInfo

/**
 * Instance of MSACDevice.
 */
@property(nonatomic) MSACDevice *device;

/**
 * Initializes a new `MSACDeviceHistoryInfo` instance.
 *
 * @param timestamp Timestamp.
 * @param device Device instance.
 */
- (instancetype)initWithTimestamp:(NSDate *)timestamp andDevice:(MSACDevice *)device;

@end
