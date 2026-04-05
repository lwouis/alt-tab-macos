// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACConstants+Internal.h"

#if __has_include(<AppCenter/MSACConstants.h>)
#import <AppCenter/MSACConstants.h>
#else
#import "MSACConstants.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface MSACChannelUnitConfiguration : NSObject

/**
 * The groupId that will be used for storage by this channel.
 */
@property(nonatomic, copy, readonly) NSString *groupId;

/**
 * The priority of logs for this channel
 */
@property(nonatomic, assign, readonly) MSACPriority priority;

/**
 * Threshold after which the queue will be flushed.
 */
@property(nonatomic, readonly) NSUInteger batchSizeLimit;

/**
 * Maximum number of batches forwarded to the ingestion at the same time.
 */
@property(nonatomic, readonly) NSUInteger pendingBatchesLimit;

/**
 * Interval for flushing the queue.
 */
@property(nonatomic, readonly) NSUInteger flushInterval;

/**
 * Initializes a new instance based on given settings.
 *
 * @param groupId The id used by the channel to determine a group of logs.
 * @param priority The priority of logs being sent by the channel.
 * @param flushInterval The interval in seconds after which a new batch will be finished. Must be between 3 and 86400 (1 day).
 * @param batchSizeLimit The maximum number of logs after which a new batch will be finished.
 * @param pendingBatchesLimit The maximum number of batches that have currently been forwarded to another component.
 *
 * @return a fully configured `MSACChannelUnitConfiguration` instance.
 */
- (instancetype)initWithGroupId:(NSString *)groupId
                       priority:(MSACPriority)priority
                  flushInterval:(NSUInteger)flushInterval
                 batchSizeLimit:(NSUInteger)batchSizeLimit
            pendingBatchesLimit:(NSUInteger)pendingBatchesLimit;

/**
 * Initializes a new instance with default settings.
 *
 * @param groupId The id used by the channel to determine a group of logs.
 *
 * @return a fully configured `MSACChannelConfiguration` instance with default settings.
 */
- (instancetype)initDefaultConfigurationWithGroupId:(NSString *)groupId;

/**
 * Initializes a new instance with flushInterval.
 *
 * @param groupId The id used by the channel to determine a group of logs.
 * @param flushInterval The interval in seconds after which a new batch will be finished. Must be between 3 and 86400 (1 day).
 *
 * @return a fully configured `MSACChannelConfiguration` instance with flushInterval.
 */
- (instancetype)initDefaultConfigurationWithGroupId:(NSString *)groupId flushInterval:(NSUInteger)flushInterval;

@end

NS_ASSUME_NONNULL_END
