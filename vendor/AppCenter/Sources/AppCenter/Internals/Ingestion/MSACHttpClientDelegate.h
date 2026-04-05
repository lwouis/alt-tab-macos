// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MSACHttpClientDelegate <NSObject>

@optional

/**
 * A method is called right before sending HTTP request.
 *
 * @param url A URL.
 * @param headers A collection of headers.
 */
- (void)willSendHTTPRequestToURL:(NSURL *)url withHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers;

@end

NS_ASSUME_NONNULL_END
