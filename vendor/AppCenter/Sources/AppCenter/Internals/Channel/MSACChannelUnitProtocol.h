// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACChannelProtocol.h"
#import "MSACConstants+Flags.h"

NS_ASSUME_NONNULL_BEGIN

@class MSACChannelUnitConfiguration;
@protocol MSACLog;

/**
 * `MSACChannelUnitProtocol` represents a kind of channel that is able to actually store/send logs (as opposed to a channel group, which
 * simply contains a collection of channel units).
 */
@protocol MSACChannelUnitProtocol <MSACChannelProtocol>

/**
 * The configuration used by this channel unit.
 */
@property(nonatomic) MSACChannelUnitConfiguration *configuration;

/**
 * Queue used to process logs.
 */
@property(nonatomic) dispatch_queue_t logsDispatchQueue;

/**
 * Enqueue a new log item.
 *
 * @param item The log item that should be enqueued.
 * @param flags Options for the item being enqueued.
 */
- (void)enqueueItem:(id<MSACLog>)item flags:(MSACFlags)flags;

/**
 * Pause sending logs with the given transmission target token.
 *
 * @param token The transmission target token.
 *
 * @discussion The logs with the given token will continue to be persisted in the storage but they will only be sent once it resumes sending
 * logs.
 *
 * @see resumeSendingLogsWithToken:
 */
- (void)pauseSendingLogsWithToken:(NSString *)token;

/**
 * Resume sending logs with the given transmission target token.
 *
 * @param token The transmission target token.
 *
 * @see pauseSendingLogsWithToken:
 */
- (void)resumeSendingLogsWithToken:(NSString *)token;

/**
 * Check for enqueued logs to send to ingestion.
 */
- (void)checkPendingLogs;

@end

NS_ASSUME_NONNULL_END
