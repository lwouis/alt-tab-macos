// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACChannelUnitProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class MSACChannelUnitConfiguration;

@protocol MSACIngestionProtocol;
@protocol MSACStorage;

@interface MSACChannelUnitDefault : NSObject <MSACChannelUnitProtocol>

/**
 * Initializes a new `MSACChannelUnitDefault` instance.
 *
 * @param ingestion An ingestion instance that is used to send batches of log items to the backend.
 * @param storage A storage instance to store and read enqueued log items.
 * @param configuration The configuration used by this channel.
 * @param logsDispatchQueue Queue used to process logs.
 *
 * @return A new `MSACChannelUnitDefault` instance.
 */
- (instancetype)initWithIngestion:(nullable id<MSACIngestionProtocol>)ingestion
                          storage:(id<MSACStorage>)storage
                    configuration:(MSACChannelUnitConfiguration *)configuration
                logsDispatchQueue:(dispatch_queue_t)logsDispatchQueue;

/**
 * Hash table of channel delegate.
 */
@property(nonatomic) NSHashTable<id<MSACChannelDelegate>> *delegates;

/**
 * An ingestion instance that is used to send batches of log items to the
 * backend.
 */
@property(nonatomic, nullable) id<MSACIngestionProtocol> ingestion;

/**
 * A storage instance to store and read enqueued log items.
 */
@property(nonatomic) id<MSACStorage> storage;

/**
 * A timer source which is used to flush the queue after a certain amount of time.
 */
@property(nonatomic) dispatch_source_t timerSource;

/**
 * A counter that keeps tracks of the number of logs added to the queue.
 */
@property(nonatomic, assign) NSUInteger itemsCount;

/**
 * A list used to keep track of batches that have been forwarded to the ingestion component.
 */
@property(nonatomic, strong) NSMutableArray *pendingBatchIds;

/**
 * A boolean value set to YES if there is at least one available batch from the storage.
 */
@property(nonatomic) BOOL availableBatchFromStorage;

/**
 * A boolean value set to YES if the pending batch queue is full.
 */
@property(nonatomic) BOOL pendingBatchQueueFull;

/**
 * A boolean value set to YES if the channel is enabled or NO otherwise.
 * Enable/disable does resume/pause the channel as needed under the hood. When a channel is disabled with data deletion it deletes persisted
 * logs and discards incoming logs.
 */
@property(nonatomic, getter=isEnabled) BOOL enabled;

/**
 * A boolean value set to YES if the channel is paused or NO otherwise. A paused channel doesn't forward logs to the ingestion. A paused
 * state doesn't impact the current enabled state.
 */
@property(nonatomic, getter=isPaused) BOOL paused;

/**
 * A boolean value set to YES if logs are discarded (not persisted) or NO otherwise. Logs are discarded when the related service is disabled
 * or an unrecoverable error happened.
 */
@property(nonatomic) BOOL discardLogs;

@end

NS_ASSUME_NONNULL_END
