// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

// Device manufacturer
static NSString *const kMSACDeviceManufacturer = @"Apple";

// HTTP method names.
static NSString *const kMSACHttpMethodGet = @"GET";
static NSString *const kMSACHttpMethodPost = @"POST";
static NSString *const kMSACHttpMethodDelete = @"DELETE";

// HTTP Headers + Query string.
static NSString *const kMSACHeaderAppSecretKey = @"App-Secret";
static NSString *const kMSACHeaderInstallIDKey = @"Install-ID";
static NSString *const kMSACHeaderContentTypeKey = @"Content-Type";
static NSString *const kMSACAppCenterContentType = @"application/json";
static NSString *const kMSACHeaderContentEncodingKey = @"Content-Encoding";
static NSString *const kMSACHeaderContentEncoding = @"gzip";
static NSString *const kMSACRetryHeaderKey = @"x-ms-retry-after-ms";

// Token obfuscation.
static NSString *const kMSACTokenKeyValuePattern = @"\"token\"\\s*:\\s*\"[^\"]+\"";
static NSString *const kMSACTokenKeyValueObfuscatedTemplate = @"\"token\" : \"***\"";

// Redirect URI obfuscation.
static NSString *const kMSACRedirectUriPattern = @"\"redirect_uri\"\\s*:\\s*\"[^\"]+\"";
static NSString *const kMSACRedirectUriObfuscatedTemplate = @"\"redirect_uri\" : \"***\"";

// Info.plist key names.
static NSString *const kMSACCFBundleURLTypes = @"CFBundleURLTypes";
static NSString *const kMSACCFBundleURLSchemes = @"CFBundleURLSchemes";
static NSString *const kMSACCFBundleTypeRole = @"CFBundleTypeRole";

// Other HTTP constants.
static short const kMSACHTTPMinGZipLength = 1400;

/**
 * Enum indicating result of a MSACIngestionCall.
 */
typedef NS_ENUM(NSInteger, MSACIngestionCallResult) {
  MSACIngestionCallResultSuccess = 100,
  MSACIngestionCallResultRecoverableError = 500,
  MSACIngestionCallResultFatalError = 999
};

/**
 * Constants for maximum number and length of log properties.
 */
/**
 * Maximum properties per log.
 */
static const int kMSACMaxPropertiesPerLog = 20;

/**
 * Minimum properties key length.
 */
static const int kMSACMinPropertyKeyLength = 1;

/**
 * Maximum properties key length.
 */
static const int kMSACMaxPropertyKeyLength = 125;

/**
 * Maximum properties value length.
 */
static const int kMSACMaxPropertyValueLength = 125;

/**
 * Maximum allowable size of a common schema log in bytes.
 */
static const long kMSACMaximumCommonSchemaLogSizeInBytes = 2 * 1024 * 1024;

/**
 * Suffix for One Collector group ID.
 */
static NSString *const kMSACOneCollectorGroupIdSuffix = @"/one";

/**
 * Bit mask for persistence flags.
 */
static const NSUInteger kMSACPersistenceFlagsMask = 0xFF;

/**
 * Common schema prefix separator used in various field values.
 */
static NSString *const kMSACCommonSchemaPrefixSeparator = @":";

/**
 * Default flush interval for channel.
 */
static NSUInteger const kMSACFlushIntervalDefault = 3;
