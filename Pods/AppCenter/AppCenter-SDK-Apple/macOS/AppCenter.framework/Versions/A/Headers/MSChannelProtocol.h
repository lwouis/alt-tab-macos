// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_CHANNEL_PROTOCOL_H
#define MS_CHANNEL_PROTOCOL_H

#import <Foundation/Foundation.h>

#import "MSEnable.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MSChannelDelegate;

/**
 * `MSChannelProtocol` contains the essential operations of a channel. Channels are broadly responsible for enqueuing logs to be sent to the
 * backend and/or stored on disk.
 */
@protocol MSChannelProtocol <NSObject, MSEnable>

/**
 * Add delegate.
 *
 * @param delegate delegate.
 */
- (void)addDelegate:(id<MSChannelDelegate>)delegate;

/**
 * Remove delegate.
 *
 * @param delegate delegate.
 */
- (void)removeDelegate:(id<MSChannelDelegate>)delegate;

/**
 * Pause operations, logs will be stored but not sent.
 *
 * @param identifyingObject Object used to identify the pause request.
 *
 * @discussion A paused channel doesn't forward logs to the ingestion. The identifying object used to pause the channel can be any unique
 * object. The same identifying object must be used to call resume. For simplicity if the caller is the one owning the channel then @c self
 * can be used as identifying object.
 *
 * @see resumeWithIdentifyingObject:
 */
- (void)pauseWithIdentifyingObject:(id<NSObject>)identifyingObject;

/**
 * Resume operations, logs can be sent again.
 *
 * @param identifyingObject Object used to passed to the pause method.
 *
 * @discussion The channel only resume when all the outstanding identifying objects have been resumed.
 *
 * @see pauseWithIdentifyingObject:
 */
- (void)resumeWithIdentifyingObject:(id<NSObject>)identifyingObject;

@end

NS_ASSUME_NONNULL_END

#endif
