// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACConstants+Flags.h"

@protocol MSACChannelUnitProtocol;
@protocol MSACChannelGroupProtocol;
@protocol MSACChannelProtocol;
@protocol MSACLog;

NS_ASSUME_NONNULL_BEGIN

@protocol MSACChannelDelegate <NSObject>

@optional

/**
 * A callback that is called when a channel unit is added to the channel group.
 *
 * @param channelGroup The channel group.
 * @param channel The newly added channel.
 */
- (void)channelGroup:(id<MSACChannelGroupProtocol>)channelGroup didAddChannelUnit:(id<MSACChannelUnitProtocol>)channel;

/**
 * A callback that is called when a log is just enqueued. Delegates may want to prepare the log a little more before further processing.
 *
 * @param log The log to prepare.
 */
- (void)channel:(id<MSACChannelProtocol>)channel prepareLog:(id<MSACLog>)log;

/**
 * A callback that is called after a log is definitely prepared.
 *
 * @param log The log.
 * @param internalId An internal Id to keep track of logs.
 * @param flags Options for the log.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didPrepareLog:(id<MSACLog>)log internalId:(NSString *)internalId flags:(MSACFlags)flags;

/**
 * A callback that is called after a log completed the enqueueing process whether it was successful or not.
 *
 * @param log The log.
 * @param internalId An internal Id to keep track of logs.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didCompleteEnqueueingLog:(id<MSACLog>)log internalId:(NSString *)internalId;

/**
 * Callback method that will be called before each log will be send to the server.
 *
 * @param channel The channel object.
 * @param log The log to be sent.
 */
- (void)channel:(id<MSACChannelProtocol>)channel willSendLog:(id<MSACLog>)log;

/**
 * Callback method that will be called in case the SDK was able to send a log.
 *
 * @param channel The channel object.
 * @param log The log to be sent.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didSucceedSendingLog:(id<MSACLog>)log;

/**
 * Callback method that will be called in case the SDK was unable to send a log.
 *
 * @param channel The channel object.
 * @param log The log to be sent.
 * @param error The error that occured.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didFailSendingLog:(id<MSACLog>)log withError:(nullable NSError *)error;

/**
 * A callback that is called when setEnabled has been invoked.
 *
 * @param channel The channel.
 * @param isEnabled The boolean that indicates enabled.
 * @param deletedData The boolean that indicates deleting data on disabled.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didSetEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deletedData;

/**
 * A callback that is called when pause has been invoked.
 *
 * @param channel The channel.
 * @param identifyingObject The identifying object used to pause the channel.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didPauseWithIdentifyingObject:(id<NSObject>)identifyingObject;

/**
 * A callback that is called when resume has been invoked.
 *
 * @param channel The channel.
 * @param identifyingObject The identifying object used to resume the channel.
 */
- (void)channel:(id<MSACChannelProtocol>)channel didResumeWithIdentifyingObject:(id<NSObject>)identifyingObject;

/**
 * Callback method that will determine if a log should be filtered out from the usual processing pipeline. If any delegate returns true, the
 * log is filtered.
 *
 * @param channelUnit The channel unit that is going to send the log.
 * @param log The log to be filtered or not.
 *
 * @return `true` if the log should be filtered out.
 */
- (BOOL)channelUnit:(id<MSACChannelUnitProtocol>)channelUnit shouldFilterLog:(id<MSACLog>)log;

@end

NS_ASSUME_NONNULL_END
