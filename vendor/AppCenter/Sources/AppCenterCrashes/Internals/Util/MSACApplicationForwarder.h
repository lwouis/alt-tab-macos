// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MSACApplicationForwarder : NSObject

/**
 * Register forwarding on `NSApplication` via swizzling.
 */
+ (void)registerForwarding;

@end

NS_ASSUME_NONNULL_END
