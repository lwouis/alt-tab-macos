// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const kMSACUserDefaultsPrefix = @"MSAppCenter";

@interface MSACAppCenterUserDefaults ()

/**
 * Resets the shared instance of the class.
 */
+ (void)resetSharedInstance;

NS_ASSUME_NONNULL_END

@end
