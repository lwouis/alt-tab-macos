// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDependencyConfiguration.h"
#import "MSACHttpClientProtocol.h"

static id<MSACHttpClientProtocol> _httpClient;

@implementation MSACDependencyConfiguration

+ (id<MSACHttpClientProtocol>)httpClient {
  @synchronized(self) {
    return _httpClient;
  }
}

+ (void)setHttpClient:(nullable id<MSACHttpClientProtocol>)httpClient {
  @synchronized(self) {
    _httpClient = httpClient;
  }
}

@end
