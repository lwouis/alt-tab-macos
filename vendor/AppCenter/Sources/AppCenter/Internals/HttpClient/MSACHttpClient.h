// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACHttpClientProtocol.h"

@interface MSACHttpClient : NSObject <MSACHttpClientProtocol>

/**
 * Creates an instance of MSACHttpClient.
 *
 * @return A new instance of MSACHttpClient.
 */
- (instancetype)init;

/**
 * Creates an instance of MSACHttpClient.
 *
 * @param maxHttpConnectionsPerHost The maximum number of connections that can be open for a single host at once.
 *
 * @return A new instance of MSACHttpClient.
 */
- (instancetype)initWithMaxHttpConnectionsPerHost:(NSInteger)maxHttpConnectionsPerHost;

@end
