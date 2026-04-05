// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACChannelDelegate.h"

@protocol MSACHttpClientProtocol;

NS_ASSUME_NONNULL_BEGIN

/**
 * One Collector channel delegate that is used to redirect selected traffic to One Collector.
 */
@interface MSACOneCollectorChannelDelegate : NSObject <MSACChannelDelegate>

/**
 * Init a `MSACOneCollectorChannelDelegate` with an install Id.
 *
 * @param httpClient HTTP client instance.
 * @param installId A device install Id.
 * @param baseUrl base url to use for backend communication.
 *
 * @return A `MSACOneCollectorChannelDelegate` instance.
 */
- (instancetype)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                         installId:(NSUUID *)installId
                           baseUrl:(nullable NSString *)baseUrl;

/**
 * Change the base URL (schema + authority + port only) that is used to communicate with the backend.
 *
 * @param logUrl base URL to use for backend communication.
 */
- (void)setLogUrl:(NSString *)logUrl;

@end

NS_ASSUME_NONNULL_END
