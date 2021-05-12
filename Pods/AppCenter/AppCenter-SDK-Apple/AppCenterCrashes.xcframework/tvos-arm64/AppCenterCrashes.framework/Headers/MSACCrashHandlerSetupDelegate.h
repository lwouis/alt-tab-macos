// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

/**
 * This is required for Wrapper SDKs that need to provide custom behavior surrounding the setup of crash handlers.
 */
NS_SWIFT_NAME(CrashHandlerSetupDelegate)
@protocol MSACCrashHandlerSetupDelegate <NSObject>

@optional

/**
 * Callback method that will be called immediately before crash handlers are set up.
 */
- (void)willSetUpCrashHandlers;

/**
 * Callback method that will be called immediately after crash handlers are set up.
 */
- (void)didSetUpCrashHandlers;

/**
 * Callback method that gets a value indicating whether the SDK should enable an uncaught exception handler.
 *
 * @return YES if SDK should enable uncaught exception handler, otherwise NO.
 *
 * @discussion Do not register an UncaughtExceptionHandler for Xamarin as we rely on the Xamarin runtime to report NSExceptions. Registering
 * our own UncaughtExceptionHandler will cause the Xamarin debugger to not work properly (it will not stop for NSExceptions).
 */
- (BOOL)shouldEnableUncaughtExceptionHandler;

@end
