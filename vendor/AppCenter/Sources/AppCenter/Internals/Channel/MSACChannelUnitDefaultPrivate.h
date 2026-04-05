// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACChannelUnitDefault.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSACChannelUnitDefault ()

@property(nonatomic) NSHashTable *pausedIdentifyingObjects;

@property(nonatomic) NSMutableSet<NSString *> *pausedTargetKeys;

/**
 * Flush pending logs.
 */
- (void)flushQueue;

/**
 * Synchronously pause operations, logs will be stored but not sent.
 *
 * @param identifyingObject Object used to identify the pause request.
 *
 * @discussion The same identifying object must be used to call resume.
 *
 * @see resumeWithIdentifyingObject:
 */
- (void)pauseWithIdentifyingObjectSync:(id<NSObject>)identifyingObject;

/**
 * Synchronously resume operations, logs can be sent again.
 *
 * @param identifyingObject Object used to passed to the pause method.
 *
 * @discussion The channel only resume when all the outstanding identifying objects have been resumed.
 *
 * @see pauseWithIdentifyingObject:
 */
- (void)resumeWithIdentifyingObjectSync:(id<NSObject>)identifyingObject;

/**
 * If we have flushInterval bigger than 3 seconds, we should subtract an oldest log's timestamp from it.
 * It is required to avoid situations when the logs are not being sent to server because time interval is too big
 * for a typical user session.
 *
 * @return Remaining interval to trigger flush.
 */
- (NSUInteger)resolveFlushInterval;

/**
 * Get a key for NSUserDefaults where the oldest pending log timestamp is stored for the channel.
 *
 * @return A key for the oldest pending log timestamp.
 */
- (NSString *)oldestPendingLogTimestampKey;

/**
 * Start timer to send logs.
 *
 * @param flushInterval delay in seconds.
 */
- (void)startTimer:(NSUInteger)flushInterval;

@end

NS_ASSUME_NONNULL_END
