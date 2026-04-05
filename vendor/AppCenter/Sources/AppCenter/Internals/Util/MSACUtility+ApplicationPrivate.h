// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACUtility+Application.h"

/**
 * Utility class that is used throughout the SDK.
 * Application private part.
 */
@interface MSACUtility (ApplicationPrivate)

/**
 * Get the shared app state.
 *
 * @return The shared app state.
 *
 * @discussion This method is exposed for testing purposes. The shared app state is resolved at runtime by this method which makes the
 * UIApplication not mockable. This method is meant to be stubbed in tests to inject the desired application states.
 */
#if TARGET_OS_OSX
+ (MSACApplicationState)sharedAppState;
#else
+ (UIApplicationState)sharedAppState;
#endif

@end
