// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACHttpClientDelegate.h"
#import "MSACIngestionProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// HTTP request/response headers for eTag.
static NSString *const kMSACETagResponseHeader = @"etag";
static NSString *const kMSACETagRequestHeader = @"If-None-Match";

@interface MSACHttpIngestion : NSObject <MSACIngestionProtocol, MSACHttpClientDelegate>

/**
 * Base URL (schema + authority + port only) used to communicate with the server.
 */
@property(nonatomic, copy) NSString *baseURL;

/**
 * API URL path used to identify an API from the server.
 */
@property(nonatomic, copy) NSString *apiPath;

/**
 * Send Url.
 */
@property(nonatomic) NSURL *sendURL;

/**
 * Request header parameters.
 */
@property(nonatomic) NSDictionary *httpHeaders;

/**
 * The HTTP Client.
 */
@property(nonatomic) id<MSACHttpClientProtocol> httpClient;

/**
 * Retrieve data payload.
 *
 * @param data The request data.
 * @param eTag The ETag.
 */
- (nullable NSDictionary *)getHeadersWithData:(nullable NSObject *)data eTag:(nullable NSString *)eTag;

/**
 * Retrieve data payload as http request body.
 *
 * @param data The request body data.
 */
- (nullable NSData *)getPayloadWithData:(nullable NSObject *)data;

/**
 * Send data to backend
 *
 * @param data A data instance that will be transformed request body.
 * @param eTag HTTP entity tag.
 * @param handler Completion handler.
 */
- (void)sendAsync:(nullable NSObject *)data eTag:(nullable NSString *)eTag completionHandler:(MSACSendAsyncCompletionHandler)handler;

/**
 * Get eTag from the given response.
 *
 * @param response HTTP response with eTag header.
 *
 * @return An eTag or `nil` if not found.
 */
+ (nullable NSString *)eTagFromResponse:(NSHTTPURLResponse *)response;

/**
 * Get the Http method to use.
 *
 * @return The http method. Defaults to POST if not overridden.
 */
- (NSString *)getHttpMethod;

/**
 * Build a new URL with the given values.
 *
 * @param baseURL Base URL for Ingestion endpoint.
 * @param apiPath A path for an API.
 * @param queryStrings An array of query strings.
 *
 * @return A complete URL with the given values.
 */
- (NSURL *)buildURLWithBaseURL:(NSString *)baseURL apiPath:(NSString *)apiPath queryStrings:(NSDictionary *)queryStrings;

@end

NS_ASSUME_NONNULL_END
