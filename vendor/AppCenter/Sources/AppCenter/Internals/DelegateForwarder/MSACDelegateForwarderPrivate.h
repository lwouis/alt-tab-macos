// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDelegateForwarder.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSACDelegateForwarder ()

/**
 * Keep track of original selectors to swizzle.
 */
@property(nonatomic, readonly) NSMutableSet<NSString *> *selectorsToSwizzle;

/**
 * Only used by tests to reset the singleton instance.
 */
+ (void)resetSharedInstance;

@end

NS_ASSUME_NONNULL_END
