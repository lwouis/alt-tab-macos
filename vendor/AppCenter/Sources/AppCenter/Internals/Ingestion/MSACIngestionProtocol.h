// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACEnable.h"
#import "MSACHttpClientProtocol.h"
#import "MSACHttpUtil.h"
#import "MSAC_Reachability.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MSACIngestionDelegate;

typedef void (^MSACSendAsyncCompletionHandler)(NSString *callId, NSHTTPURLResponse *_Nullable response, NSData *_Nullable data,
                                               NSError *_Nullable error);

@protocol MSACIngestionProtocol <NSObject, MSACEnable>

/**
 * The indicator of readiness to send data.
 */
@property(nonatomic, readonly, getter=isReadyToSend) BOOL readyToSend;

/**
 * A boolean value set to YES if the ingestion is enabled or NO otherwise.
 * Enable/disable does resume/pause the ingestion as needed under the hood.
 */
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;

/**
 * Send data.
 *
 * @param data Instance that will be transformed to request body.
 * @param handler Completion handler.
 */
- (void)sendAsync:(nullable NSObject *)data completionHandler:(MSACSendAsyncCompletionHandler)handler;

/**
 * Send data.
 *
 * @param data Instance that will be transformed to request body.
 * @param eTag HTTP entity tag.
 * @param handler Completion handler.
 */
- (void)sendAsync:(nullable NSObject *)data eTag:(nullable NSString *)eTag completionHandler:(MSACSendAsyncCompletionHandler)handler;

@end

NS_ASSUME_NONNULL_END
