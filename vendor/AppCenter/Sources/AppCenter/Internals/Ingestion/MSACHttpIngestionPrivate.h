// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACHttpIngestion.h"

@interface MSACHttpIngestion ()

/**
 * The maximum number of connections for the session. The one collector endpoint only allows for two connections while the app center
 * endpoint doesn't impose a limit, using the iOS default value of 4 connections for this.
 */
@property(nonatomic, readonly) NSInteger maxNumberOfConnections;

/**
 * Retry intervals used by calls in case of recoverable errors.
 */
@property(nonatomic) NSArray *callsRetryIntervals;

/**
 * A boolean value set to YES if the ingestion is enabled or NO otherwise.
 * Enable/disable does resume/pause the ingestion as needed under the hood.
 */
@property(nonatomic, getter=isEnabled) BOOL enabled;

/**
 * Initialize the Ingestion with default retry intervals.
 *
 * @param httpClient The HTTP client.
 * @param baseUrl Base url.
 * @param apiPath Base API path.
 * @param headers HTTP headers.
 * @param queryStrings An array of query strings.
 */
- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                 baseUrl:(NSString *)baseUrl
                 apiPath:(NSString *)apiPath
                 headers:(NSDictionary *)headers
            queryStrings:(NSDictionary *)queryStrings;

/**
 * Initialize the Ingestion.
 *
 * @param httpClient The HTTP client.
 * @param baseUrl Base url.
 * @param apiPath Base API path.
 * @param headers Http headers.
 * @param queryStrings An array of query strings.
 * @param retryIntervals An array for retry intervals in second.
 */
- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                 baseUrl:(NSString *)baseUrl
                 apiPath:(NSString *)apiPath
                 headers:(NSDictionary *)headers
            queryStrings:(NSDictionary *)queryStrings
          retryIntervals:(NSArray *)retryIntervals;

/**
 * Initialize the Ingestion.
 *
 * @param httpClient The HTTP client.
 * @param baseUrl Base url.
 * @param apiPath Base API path.
 * @param headers Http headers.
 * @param queryStrings An array of query strings.
 * @param retryIntervals An array for retry intervals in second.
 * @param maxNumberOfConnections The maximum number of connections per host.
 */
- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient
                   baseUrl:(NSString *)baseUrl
                   apiPath:(NSString *)apiPath
                   headers:(NSDictionary *)headers
              queryStrings:(NSDictionary *)queryStrings
            retryIntervals:(NSArray *)retryIntervals
    maxNumberOfConnections:(NSInteger)maxNumberOfConnections;

/**
 * Hide a part of sensitive value for payload.
 *
 * @param payload The response payload to be obfuscated.
 *
 * @return An obfuscated value.
 */
- (NSString *)obfuscateResponsePayload:(NSString *)payload;

/**
 * Gets the HTTP payload for the given data.
 *
 * @param data The data object.
 *
 * @return The serialized HTTP data.
 */
- (NSData *)getPayloadWithData:(NSObject *)data;

@end
