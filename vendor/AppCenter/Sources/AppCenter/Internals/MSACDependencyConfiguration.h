// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@protocol MSACHttpClientProtocol;

NS_ASSUME_NONNULL_BEGIN

@interface MSACDependencyConfiguration : NSObject

@property(class, nonatomic, nullable) id<MSACHttpClientProtocol> httpClient;

@end

NS_ASSUME_NONNULL_END
