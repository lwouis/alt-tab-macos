// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACChannelGroupProtocol.h"
#import "MSACDeviceTracker.h"

NS_ASSUME_NONNULL_BEGIN

@class MSACAppCenterIngestion;

@protocol MSACHttpClientProtocol;
@protocol MSACStorage;

/**
 * A channel group which triggers and manages the processing of log items on different channels. All items will be immediately passed to the
 * persistence layer in order to make the queue crash safe. Once a maximum number of items have been enqueued or the internal timer finished
 * running, events will be forwarded to the ingestion. Furthermore, its responsibility is to tell the persistence layer what to do with a
 * pending batch based on the status code returned by the ingestion
 */
@interface MSACChannelGroupDefault : NSObject <MSACChannelGroupProtocol>

/**
 * Initializes a new `MSACChannelGroupDefault` instance.
 *
 * @param httpClient The HTTP client.
 * @param installId A unique installation identifier.
 * @param logUrl A base URL to use for backend communication.
 *
 * @return A new `MSACChannelGroupDefault` instance.
 */
- (instancetype)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient installId:(NSUUID *)installId logUrl:(NSString *)logUrl;

/**
 * Collection of channel delegates.
 */
@property(nonatomic) NSHashTable<id<MSACChannelDelegate>> *delegates;

/**
 * An ingestion instance that is used to send batches of log items to the backend.
 */
@property(nonatomic, strong, nullable) MSACAppCenterIngestion *ingestion;

/**
 * A storage instance to store and read enqueued log items.
 */
@property(nonatomic, strong) id<MSACStorage> storage;

/**
 * A queue which makes adding new items thread safe.
 */
@property(nonatomic, strong) dispatch_queue_t logsDispatchQueue;

/**
 * An array containing all channels that are a part of this channel group.
 */
@property(nonatomic, strong) NSMutableArray *channels;

@end

NS_ASSUME_NONNULL_END
