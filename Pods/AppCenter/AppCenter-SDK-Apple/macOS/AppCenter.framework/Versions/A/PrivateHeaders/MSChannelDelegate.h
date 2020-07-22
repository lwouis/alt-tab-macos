// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSConstants+Flags.h"

@protocol MSChannelUnitProtocol;
@protocol MSChannelGroupProtocol;
@protocol MSChannelProtocol;
@protocol MSLog;

@protocol MSChannelDelegate <NSObject>

@optional

/**
 * A callback that is called when a channel unit is added to the channel group.
 *
 * @param channelGroup The channel group.
 * @param channel The newly added channel.
 */
- (void)channelGroup:(id<MSChannelGroupProtocol>)channelGroup didAddChannelUnit:(id<MSChannelUnitProtocol>)channel;

/**
 * A callback that is called when a log is just enqueued. Delegates may want to prepare the log a little more before further processing.
 *
 * @param log The log to prepare.
 */
- (void)channel:(id<MSChannelProtocol>)channel prepareLog:(id<MSLog>)log;

/**
 * A callback that is called after a log is definitely prepared.
 *
 * @param log The log.
 * @param internalId An internal Id to keep track of logs.
 * @param flags Options for the log.
 */
- (void)channel:(id<MSChannelProtocol>)channel didPrepareLog:(id<MSLog>)log internalId:(NSString *)internalId flags:(MSFlags)flags;

/**
 * A callback that is called after a log completed the enqueueing process whether it was successful or not.
 *
 * @param log The log.
 * @param internalId An internal Id to keep track of logs.
 */
- (void)channel:(id<MSChannelProtocol>)channel didCompleteEnqueueingLog:(id<MSLog>)log internalId:(NSString *)internalId;

/**
 * Callback method that will be called before each log will be send to the server.
 *
 * @param channel The channel object.
 * @param log The log to be sent.
 */
- (void)channel:(id<MSChannelProtocol>)channel willSendLog:(id<MSLog>)log;

/**
 * Callback method that will be called in case the SDK was able to send a log.
 *
 * @param channel The channel object.
 * @param log The log to be sent.
 */
- (void)channel:(id<MSChannelProtocol>)channel didSucceedSendingLog:(id<MSLog>)log;

/**
 * Callback method that will be called in case the SDK was unable to send a log.
 *
 * @param channel The channel object.
 * @param log The log to be sent.
 * @param error The error that occured.
 */
- (void)channel:(id<MSChannelProtocol>)channel didFailSendingLog:(id<MSLog>)log withError:(NSError *)error;

/**
 * A callback that is called when setEnabled has been invoked.
 *
 * @param channel The channel.
 * @param isEnabled The boolean that indicates enabled.
 * @param deletedData The boolean that indicates deleting data on disabled.
 */
- (void)channel:(id<MSChannelProtocol>)channel didSetEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deletedData;

/**
 * A callback that is called when pause has been invoked.
 *
 * @param channel The channel.
 * @param identifyingObject The identifying object used to pause the channel.
 */
- (void)channel:(id<MSChannelProtocol>)channel didPauseWithIdentifyingObject:(id<NSObject>)identifyingObject;

/**
 * A callback that is called when resume has been invoked.
 *
 * @param channel The channel.
 * @param identifyingObject The identifying object used to resume the channel.
 */
- (void)channel:(id<MSChannelProtocol>)channel didResumeWithIdentifyingObject:(id<NSObject>)identifyingObject;

/**
 * Callback method that will determine if a log should be filtered out from the usual processing pipeline. If any delegate returns true, the
 * log is filtered.
 *
 * @param channelUnit The channel unit that is going to send the log.
 * @param log The log to be filtered or not.
 *
 * @return `true` if the log should be filtered out.
 */
- (BOOL)channelUnit:(id<MSChannelUnitProtocol>)channelUnit shouldFilterLog:(id<MSLog>)log;

@end
