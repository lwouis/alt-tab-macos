// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_CHANNEL_GROUP_PROTOCOL_H
#define MS_CHANNEL_GROUP_PROTOCOL_H

#import <Foundation/Foundation.h>

#import "MSChannelProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class MSChannelUnitConfiguration;

@protocol MSIngestionProtocol;
@protocol MSChannelUnitProtocol;

/**
 * `MSChannelGroupProtocol` represents a kind of channel that contains constituent MSChannelUnit objects. When an operation from the
 * `MSChannelProtocol` is performed on the group, that operation should be propagated to its constituent MSChannelUnit objects.
 */
@protocol MSChannelGroupProtocol <MSChannelProtocol>

/**
 * Initialize a channel unit with the given configuration.
 *
 * @param configuration channel configuration.
 *
 * @return The added `MSChannelUnitProtocol`. Use this object to enqueue logs.
 */
- (id<MSChannelUnitProtocol>)addChannelUnitWithConfiguration:(MSChannelUnitConfiguration *)configuration;

/**
 * Initialize a channel unit with the given configuration.
 *
 * @param configuration channel configuration.
 * @param ingestion The alternative ingestion object
 *
 * @return The added `MSChannelUnitProtocol`. Use this object to enqueue logs.
 */
- (id<MSChannelUnitProtocol>)addChannelUnitWithConfiguration:(MSChannelUnitConfiguration *)configuration
                                               withIngestion:(nullable id<MSIngestionProtocol>)ingestion;

/**
 * Change the base URL (schema + authority + port only) used to communicate with the backend.
 *
 * @param logUrl base URL to use for backend communication.
 */
- (void)setLogUrl:(NSString *)logUrl;

/**
 * Set the app secret.
 *
 * @param appSecret The app secret.
 */
- (void)setAppSecret:(NSString *)appSecret;

/**
 * Set the maximum size of the internal storage. This method must be called before App Center is started.
 *
 * @discussion The default maximum database size is 10485760 bytes (10 MiB).
 *
 * @param sizeInBytes Maximum size of the internal storage in bytes. This will be rounded up to the nearest multiple of a SQLite page size
 * (default is 4096 bytes). Values below 24576 bytes (24 KiB) will be ignored.
 * @param completionHandler Callback that is invoked when the database size has been set. The `BOOL` parameter is `YES` if changing the size
 * is successful, and `NO` otherwise.
 */
- (void)setMaxStorageSize:(long)sizeInBytes completionHandler:(nullable void (^)(BOOL))completionHandler;

/**
 * Return a channel unit instance for the given groupId.
 *
 * @param groupId The group ID for a channel unit.
 *
 * @return A channel unit instance or `nil`.
 */
- (nullable id<MSChannelUnitProtocol>)channelUnitForGroupId:(NSString *)groupId;

@end

NS_ASSUME_NONNULL_END

#endif
