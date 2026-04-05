// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCustomApplicationDelegate.h"
#import "MSACDelegateForwarder.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const kMSACAppDelegateForwarderEnabledKey = @"AppCenterAppDelegateForwarderEnabled";

@interface MSACAppDelegateForwarder : MSACDelegateForwarder <MSACCustomApplicationDelegate>

@end

NS_ASSUME_NONNULL_END
