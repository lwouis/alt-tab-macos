// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_DEVICE_INTERNAL_H
#define MSAC_DEVICE_INTERNAL_H

#import <Foundation/Foundation.h>

#import "MSACAbstractLogInternal.h"
#import "MSACDevice.h"

static NSString *const kMSACSDKName = @"sdkName";
static NSString *const kMSACSDKVersion = @"sdkVersion";
static NSString *const kMSACModel = @"model";
static NSString *const kMSACOEMName = @"oemName";
static NSString *const kMSACACOSName = @"osName";
static NSString *const kMSACOSVersion = @"osVersion";
static NSString *const kMSACOSBuild = @"osBuild";
static NSString *const kMSACOSAPILevel = @"osApiLevel";
static NSString *const kMSACLocale = @"locale";
static NSString *const kMSACTimeZoneOffset = @"timeZoneOffset";
static NSString *const kMSACScreenSize = @"screenSize";
static NSString *const kMSACAppVersion = @"appVersion";
static NSString *const kMSACCarrierName = @"carrierName";
static NSString *const kMSACCarrierCountry = @"carrierCountry";
static NSString *const kMSACAppBuild = @"appBuild";
static NSString *const kMSACAppNamespace = @"appNamespace";

@interface MSACDevice () <MSACSerializableObject>

/*
 * Name of the SDK. Consists of the name of the SDK and the platform, e.g. "appcenter.ios", "appcenter.android"
 */
@property(nonatomic, copy) NSString *sdkName;

/*
 * Version of the SDK in semver format, e.g. "1.2.0" or "0.12.3-alpha.1".
 */
@property(nonatomic, copy) NSString *sdkVersion;

/*
 * Device model (example: iPad2,3).
 */
@property(nonatomic, copy) NSString *model;

/*
 * Device manufacturer (example: HTC).
 */
@property(nonatomic, copy) NSString *oemName;

/*
 * OS name (example: iOS).
 */
@property(nonatomic, copy) NSString *osName;

/*
 * OS version (example: 9.3.0).
 */
@property(nonatomic, copy) NSString *osVersion;

/*
 * OS build code (example: LMY47X). [optional]
 */
@property(nonatomic, copy) NSString *osBuild;

/*
 * API level when applicable like in Android (example: 15). [optional]
 */
@property(nonatomic, copy) NSNumber *osApiLevel;

/*
 * Language code (example: en_US).
 */
@property(nonatomic, copy) NSString *locale;

/*
 * The offset in minutes from UTC for the device time zone, including daylight savings time.
 */
@property(nonatomic) NSNumber *timeZoneOffset;

/*
 * Screen size of the device in pixels (example: 640x480).
 */
@property(nonatomic, copy) NSString *screenSize;

/*
 * Application version name, e.g. 1.1.0
 */
@property(nonatomic, copy) NSString *appVersion;

/*
 * Carrier name (for mobile devices). [optional]
 */
@property(nonatomic, copy) NSString *carrierName;

/*
 * Carrier country code (for mobile devices). [optional]
 */
@property(nonatomic, copy) NSString *carrierCountry;

/*
 * The app's build number, e.g. 42.
 */
@property(nonatomic, copy) NSString *appBuild;

/*
 * The bundle identifier, package identifier, or namespace, depending on what the individual plattforms use, .e.g com.microsoft.example.
 * [optional]
 */
@property(nonatomic, copy) NSString *appNamespace;

@end

#endif
