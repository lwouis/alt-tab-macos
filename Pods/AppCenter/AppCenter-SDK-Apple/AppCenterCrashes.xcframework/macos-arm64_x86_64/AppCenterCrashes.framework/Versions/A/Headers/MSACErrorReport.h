// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@class MSACDevice;

NS_SWIFT_NAME(ErrorReport)
@interface MSACErrorReport : NSObject

/**
 * UUID for the crash report.
 */
@property(nonatomic, copy, readonly) NSString *incidentIdentifier;

/**
 * UUID for the app installation on the device.
 */
@property(nonatomic, copy, readonly) NSString *reporterKey;

/**
 * Signal that caused the crash.
 */
@property(nonatomic, copy, readonly) NSString *signal;

/**
 * Exception name that triggered the crash, nil if the crash was not caused by an exception.
 */
@property(nonatomic, copy, readonly) NSString *exceptionName;

/**
 * Exception reason, nil if the crash was not caused by an exception.
 */
@property(nonatomic, copy, readonly) NSString *exceptionReason;

/**
 * Date and time the app started, nil if unknown.
 */
@property(nonatomic, readonly, strong) NSDate *appStartTime;

/**
 * Date and time the error occurred, nil if unknown
 */
@property(nonatomic, readonly, strong) NSDate *appErrorTime;

/**
 * Device information of the app when it crashed.
 */
@property(nonatomic, readonly, strong) MSACDevice *device;

/**
 * Identifier of the app process that crashed.
 */
@property(nonatomic, readonly, assign) NSUInteger appProcessIdentifier;

/**
 * Indicates if the app was killed while being in foreground from the iOS.
 *
 * This can happen if it consumed too much memory or the watchdog killed the app because it took too long to startup or blocks the main
 * thread for too long, or other reasons. See Apple documentation:
 * https://developer.apple.com/library/ios/qa/qa1693/_index.html.
 *
 * @see `[MSACCrashes didReceiveMemoryWarningInLastSession]`
 */
@property(nonatomic, readonly) BOOL isAppKill;

@end
