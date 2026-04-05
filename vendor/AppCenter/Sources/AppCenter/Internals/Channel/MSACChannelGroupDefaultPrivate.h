// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACChannelDelegate.h"

NS_ASSUME_NONNULL_BEGIN

@class MSACAppCenterIngestion;
@class UIApplication;

@interface MSACChannelGroupDefault () <MSACChannelDelegate>

/**
 * Initializes a new `MSACChannelGroupDefault` instance.
 *
 * @param ingestion An HTTP ingestion instance that is used to send batches of log items to the backend.
 *
 * @return A new `MSACChannelGroupDefault` instance.
 */
- (instancetype)initWithIngestion:(nullable MSACAppCenterIngestion *)ingestion;

#if !TARGET_OS_OSX

/**
 * Called when applciation is terminating.
 */
- (void)applicationWillTerminate:(UIApplication *)application;

#endif

@end

NS_ASSUME_NONNULL_END
