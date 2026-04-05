// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_DEVICE_TRACKER_PRIVATE_H
#define MSAC_DEVICE_TRACKER_PRIVATE_H

#if TARGET_OS_IOS
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#endif

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#import <sys/sysctl.h>

#import "MSACDeviceInternal.h"
#import "MSACDeviceTracker.h"
#import "MSACWrapperSdk.h"

/**
 * Key for device history.
 */
static NSString *const kMSACPastDevicesKey = @"PastDevices";

@class MSACDeviceHistoryInfo;

@interface MSACDeviceTracker ()

/**
 * History of past devices.
 */
@property(nonatomic) NSMutableArray<MSACDeviceHistoryInfo *> *deviceHistory;

/**
 * Reset singleton instance.
 */
+ (void)resetSharedInstance;

/**
 * Sets a flag that will cause MSACDeviceTracker to update it's device info the next time the device property is accessed. Mostly intended
 * for Unit Testing.
 */
+ (void)refreshDeviceNextTime;

/**
 * Get device model.
 *
 * @return The device model as an NSString.
 */
- (NSString *)deviceModel;

#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
/**
 * Get the OS name.
 *
 * @return The OS name as an NSString.
 */
- (NSString *)osName;
#else
/**
 * Get the OS name.
 *
 * @param device Current UIDevice.
 *
 * @return The OS name as an NSString.
 */
- (NSString *)osName:(UIDevice *)device;
#endif

#if TARGET_OS_OSX
/**
 * Get the OS version.
 *
 * @return The OS version as an NSString.
 */
- (NSString *)osVersion;
#else
/**
 * Get the OS version.
 *
 * @param device Current UIDevice.
 *
 * @return The OS version as an NSString.
 */
- (NSString *)osVersion:(UIDevice *)device;
#endif

/**
 * Get the device current locale.
 *
 * @param deviceLocale Device current locale.
 *
 * @return The device current locale as an NSString.
 */
- (NSString *)locale:(NSLocale *)deviceLocale;

/**
 * Get the device current timezone offset (UTC as reference).
 *
 * @param timeZone Device timezone.
 *
 * @return The device current timezone offset as an NSNumber.
 */
- (NSNumber *)timeZoneOffset:(NSTimeZone *)timeZone;

/**
 * Get the rendered screen size.
 *
 * @return The size of the screen as an NSString with format "HEIGHTxWIDTH".
 */
- (NSString *)screenSize;

#if TARGET_OS_IOS
/**
 * Get the network carrier name.
 *
 * @param carrier Network carrier.
 *
 * @return The network carrier name as an NSString.
 */
- (NSString *)carrierName:(CTCarrier *)carrier;

/**
 * Get the network carrier country.
 *
 * @param carrier Network carrier.
 *
 * @return The network carrier country as an NSString.
 */
- (NSString *)carrierCountry:(CTCarrier *)carrier;
#endif

/**
 * Get the application version.
 *
 * @param appBundle Application main bundle.
 *
 * @return The application version as an NSString.
 */
- (NSString *)appVersion:(NSBundle *)appBundle;

/**
 * Get the application build.
 *
 * @param appBundle Application main bundle.
 *
 * @return The application build as an NSString.
 */
- (NSString *)appBuild:(NSBundle *)appBundle;

/**
 * Get the application bundle ID.
 *
 * @param appBundle Application main bundle.
 *
 * @return The application bundle ID as an NSString.
 */
- (NSString *)appNamespace:(NSBundle *)appBundle;

/**
 * Set wrapper SDK information to use when building device properties.
 *
 * @param wrapperSdk wrapper SDK information.
 */
- (void)setWrapperSdk:(MSACWrapperSdk *)wrapperSdk;

/**
 * Set country code to use when building device properties.
 *
 * @param countryCode The two-letter ISO country code. @see https://www.iso.org/obp/ui/#search for more information.
 */
- (void)setCountryCode:(NSString *)countryCode;

/**
 * Get country code.
 *
 * @return country code.
 */
- (NSString *)countryCode;

/**
 * Get wrapper SDK.
 *
 * @return wrapper sdk.
 */
- (MSACWrapperSdk *)wrapperSdk;

/**
 * Return a new Instance of MSACDevice.
 *
 * @returns A new Instance of MSACDevice. @see MSACDevice
 *
 * @discussion Intended to be used to update the device-property of MSACDeviceTracker @see MSACDeviceTracker.
 */
- (MSACDevice *)updatedDevice;

/**
 * Return a device from the history of past devices. This will be used e.g. for Crashes after relaunch.
 *
 * @param timestamp Timestamp that will be used to find a matching MSACDevice in history.
 *
 * @return Instance of MSACDevice that's closest to timestamp.
 *
 * @discussion If we cannot find a device that's within the range of the timestamp, the latest device from history will be returned. If
 * there is no history, we return the current MSACDevice.
 */
- (MSACDevice *)deviceForTimestamp:(NSDate *)timestamp;

@end

#endif
