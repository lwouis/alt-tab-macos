// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_CHANNEL_GROUP_PROTOCOL_H
#define MSAC_CHANNEL_GROUP_PROTOCOL_H

#import <Foundation/Foundation.h>

#if __has_include(<AppCenter/MSACChannelProtocol.h>)
#import <AppCenter/MSACChannelProtocol.h>
#else
#import "MSACChannelProtocol.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@class MSACChannelUnitConfiguration;

@protocol MSACIngestionProtocol;
@protocol MSACChannelUnitProtocol;

/**
 * `MSACChannelGroupProtocol` represents a kind of channel that contains constituent MSACChannelUnit objects. When an operation from the
 * `MSACChannelProtocol` is performed on the group, that operation should be propagated to its constituent MSACChannelUnit objects.
 */
NS_SWIFT_NAME(ChannelGroupProtocol)
@protocol MSACChannelGroupProtocol <MSACChannelProtocol>

/**
 * Initialize a channel unit with the given configuration.
 *
 * @param configuration channel configuration.
 *
 * @return The added `MSACChannelUnitProtocol`. Use this object to enqueue logs.
 */
- (id<MSACChannelUnitProtocol>)addChannelUnitWithConfiguration:(MSACChannelUnitConfiguration *)configuration
    NS_SWIFT_NAME(addChannelUnit(withConfiguration:));

/**
 * Initialize a channel unit with the given configuration.
 *
 * @param configuration channel configuration.
 * @param ingestion The alternative ingestion object
 *
 * @return The added `MSACChannelUnitProtocol`. Use this object to enqueue logs.
 */
- (id<MSACChannelUnitProtocol>)addChannelUnitWithConfiguration:(MSACChannelUnitConfiguration *)configuration
                                                 withIngestion:(nullable id<MSACIngestionProtocol>)ingestion
    NS_SWIFT_NAME(addChannelUnit(_:ingestion:));

/**
 * Change the base URL (schema + authority + port only) used to communicate with the backend.
 */
@property(nonatomic, strong) NSString *_Nullable logUrl;

/**
 * Set the app secret.
 */
@property(nonatomic, strong) NSString *_Nullable appSecret;

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
- (void)setMaxStorageSize:(long)sizeInBytes
        completionHandler:(nullable void (^)(BOOL))completionHandler NS_SWIFT_NAME(setMaxStorageSize(_:completionHandler:));

/**
 * Return a channel unit instance for the given groupId.
 *
 * @param groupId The group ID for a channel unit.
 *
 * @return A channel unit instance or `nil`.
 */
- (nullable id<MSACChannelUnitProtocol>)channelUnitForGroupId:(NSString *)groupId;

@end

NS_ASSUME_NONNULL_END

#endif
