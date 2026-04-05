// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#import "MSACUtility.h"

#if !TARGET_OS_OSX
#define MSAC_DEVICE [UIDevice currentDevice]
#endif

/*
 * Workaround for exporting symbols from category object files.
 */
extern NSString *MSACUtilityApplicationCategory;

/**
 *  App states
 */
typedef NS_ENUM(NSInteger, MSACApplicationState) {

/**
 * Application is active.
 */
#if TARGET_OS_OSX
  MSACApplicationStateActive,
#else
  MSACApplicationStateActive = UIApplicationStateActive,
#endif

/**
 * Application is inactive.
 */
#if TARGET_OS_OSX
  MSACApplicationStateInactive,
#else
  MSACApplicationStateInactive = UIApplicationStateInactive,
#endif

/**
 * Application is in background.
 */
#if TARGET_OS_OSX
  MSACApplicationStateBackground,
#else
  MSACApplicationStateBackground = UIApplicationStateBackground,
#endif

  /**
   * Application state can't be determined.
   */
  MSACApplicationStateUnknown
};

typedef NS_ENUM(NSInteger, MSACOpenURLState) {

  /**
   * Not being able to determine whether a URL has been processed or not.
   */
  MSACOpenURLStateUnknown,

  /**
   * A URL has been processed successfully.
   */
  MSACOpenURLStateSucceed,

  /**
   * A URL could not be processed.
   */
  MSACOpenURLStateFailed
};

/**
 * Utility class that is used throughout the SDK.
 * Application part.
 */
@interface MSACUtility (Application)

/**
 * Get the Shared Application from either NSApplication (MacOS) or UIApplication.
 *
 * @return The shared application.
 */
#if TARGET_OS_OSX
+ (NSApplication *)sharedApp;
#else
+ (UIApplication *)sharedApp;
#endif

/**
 * Get the App Delegate.
 *
 * @return The delegate of the app object or nil if not accessible.
 */
#if TARGET_OS_OSX
+ (id<NSApplicationDelegate>)sharedAppDelegate;
#else
+ (id<UIApplicationDelegate>)sharedAppDelegate;
#endif

/**
 * Get current application state.
 *
 * @return Current state of the application or MSACApplicationStateUnknown while the state can't be determined.
 *
 * @discussion The application state may not be available anywhere. Application extensions doesn't have it for instance, in that case the
 * MSACApplicationStateUnknown value is returned.
 */
+ (MSACApplicationState)applicationState;

/**
 * Attempt to open the URL asynchronously.
 *
 * @param url The URL to open.
 * @param options A dictionary of options to use when opening the URL.
 * @param completion The block to execute with the results.
 */
+ (void)sharedAppOpenUrl:(NSURL *)url
                 options:(NSDictionary<NSString *, id> *)options
       completionHandler:(void (^)(MSACOpenURLState state))completion;

@end
