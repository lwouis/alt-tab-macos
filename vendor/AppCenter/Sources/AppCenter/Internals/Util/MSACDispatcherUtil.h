// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#define MSAC_DISPATCH_SELECTOR(declaration, object, selectorName, ...)                                                                     \
  ({                                                                                                                                       \
    SEL selector = NSSelectorFromString(@ #selectorName);                                                                                  \
    IMP impl = [object methodForSelector:selector];                                                                                        \
    (declaration impl)(object, selector, ##__VA_ARGS__);                                                                                   \
  })

@interface MSACDispatcherUtil : NSObject

+ (void)performBlockOnMainThread:(void (^)(void))block;

/**
 * Adds a dispatch_async block to the provided queue and waits for its execution.
 * @param timeout Timeout for waiting in seconds.
 * @param dispatchQueue The queue to perform a block on.
 * @param block The block to be executed.
 */
+ (void)dispatchSyncWithTimeout:(NSTimeInterval)timeout onQueue:(dispatch_queue_t)dispatchQueue withBlock:(dispatch_block_t)block;

@end
