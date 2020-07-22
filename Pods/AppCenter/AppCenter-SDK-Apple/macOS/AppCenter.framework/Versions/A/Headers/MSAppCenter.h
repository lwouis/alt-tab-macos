// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSConstants.h"

@class MSWrapperSdk;

#if !TARGET_OS_TV
@class MSCustomProperties;
#endif

@interface MSAppCenter : NSObject

/**
 * Returns the singleton instance of MSAppCenter.
 */
+ (instancetype)sharedInstance;

/**
 * Configure the SDK with an application secret.
 *
 * @param appSecret A unique and secret key used to identify the application.
 *
 * @discussion This may be called only once per application process lifetime.
 */
+ (void)configureWithAppSecret:(NSString *)appSecret;

/**
 * Configure the SDK.
 *
 * @discussion This may be called only once per application process lifetime.
 */
+ (void)configure;

/**
 * Configure the SDK with an application secret and an array of services to start.
 *
 * @param appSecret A unique and secret key used to identify the application.
 * @param services  Array of services to start.
 *
 * @discussion This may be called only once per application process lifetime.
 */
+ (void)start:(NSString *)appSecret withServices:(NSArray<Class> *)services;

/**
 * Start the SDK with an array of services.
 *
 * @param services  Array of services to start.
 *
 * @discussion This may be called only once per application process lifetime.
 */
+ (void)startWithServices:(NSArray<Class> *)services;

/**
 * Start a service.
 *
 * @param service  A service to start.
 *
 * @discussion This may be called only once per service per application process lifetime.
 */
+ (void)startService:(Class)service;

/**
 * Configure the SDK with an array of services to start from a library. This will not start the service at application level, it will enable
 * the service only for the library.
 *
 * @param services Array of services to start.
 */
+ (void)startFromLibraryWithServices:(NSArray<Class> *)services;

/**
 * Check whether the SDK has already been configured or not.
 *
 * @return YES if configured, NO otherwise.
 */
+ (BOOL)isConfigured;

/**
 * Check whether app is running in App Center Test Cloud.
 *
 * @return true if running in App Center Test Cloud, false otherwise.
 */
+ (BOOL)isRunningInAppCenterTestCloud;

/**
 * Change the base URL (schema + authority + port only) used to communicate with the backend.
 *
 * @param logUrl Base URL to use for backend communication.
 */
+ (void)setLogUrl:(NSString *)logUrl;

/**
 * Enable or disable the SDK as a whole. In addition to AppCenter resources, it will also enable or disable all registered services.
 * The state is persisted in the device's storage across application launches.
 *
 * @param isEnabled YES to enable, NO to disable.
 *
 * @see isEnabled
 */
+ (void)setEnabled:(BOOL)isEnabled;

/**
 * Check whether the SDK is enabled or not as a whole.
 *
 * @return YES if enabled, NO otherwise.
 *
 * @see setEnabled:
 */
+ (BOOL)isEnabled;

/**
 * Get log level.
 *
 * @return Log level.
 */
+ (MSLogLevel)logLevel;

/**
 * Set log level.
 *
 * @param logLevel The log level.
 */
+ (void)setLogLevel:(MSLogLevel)logLevel;

/**
 * Set log level handler.
 *
 * @param logHandler Handler.
 */
+ (void)setLogHandler:(MSLogHandler)logHandler;

/**
 * Set wrapper SDK information to use when building device properties. This is intended in case you are building a SDK that uses the App
 * Center SDK under the hood, e.g. our Xamarin SDK or ReactNative SDk.
 *
 * @param wrapperSdk Wrapper SDK information.
 */
+ (void)setWrapperSdk:(MSWrapperSdk *)wrapperSdk;

#if !TARGET_OS_TV
/**
 * Set the custom properties.
 *
 * @param customProperties Custom properties object.
 */
+ (void)setCustomProperties:(MSCustomProperties *)customProperties;
#endif

/**
 * Check whether the application delegate forwarder is enabled or not.
 *
 * @return YES if enabled, NO otherwise.
 *
 * @discussion The application delegate forwarder forwards messages that target your application delegate methods via swizzling to the SDK.
 * It simplifies the SDK integration but may not be suitable to any situations. For
 * instance it should be disabled if you or one of your third party SDK is doing message forwarding on the application delegate. Message
 * forwarding usually implies the implementation of @see NSObject#forwardingTargetForSelector: or @see NSObject#forwardInvocation: methods.
 * To disable the application delegate forwarder just add the `AppCenterAppDelegateForwarderEnabled` tag to your Info .plist file and set it
 * to `0`. Then you will have to forward any application delegate needed by the SDK manually.
 */
+ (BOOL)isAppDelegateForwarderEnabled;

/**
 * Get unique installation identifier.
 *
 * @return Unique installation identifier.
 */
+ (NSUUID *)installId;

/**
 * Detect if a debugger is attached to the app process. This is only invoked once on app startup and can not detect
 * if the debugger is being attached during runtime!
 *
 * @return BOOL if the debugger is attached.
 */
+ (BOOL)isDebuggerAttached;

/**
 * Get the current version of AppCenter SDK.
 *
 * @return The current version of AppCenter SDK.
 */
+ (NSString *)sdkVersion;

/**
 * Set the maximum size of the internal storage. This method must be called before App Center is started. This method is only intended for
 * applications.
 *
 * @param sizeInBytes Maximum size of the internal storage in bytes. This will be rounded up to the nearest multiple of a SQLite page size
 * (default is 4096 bytes). Values below 20,480 bytes (20 KiB) will be ignored.
 *
 * @param completionHandler Callback that is invoked when the database size has been set. The `BOOL` parameter is `YES` if changing the size
 * is successful, and `NO` otherwise. This parameter can be null.
 *
 * @discussion This only sets the maximum size of the database, but App Center modules might store additional data.
 * The value passed to this method is not persisted on disk. The default maximum database size is 10485760 bytes (10 MiB).
 */
+ (void)setMaxStorageSize:(long)sizeInBytes completionHandler:(void (^)(BOOL))completionHandler;

/**
 * Set the user identifier.
 *
 * @param userId User identifier.
 *
 * @discussion Set the user identifier for logs sent for the default target token when the secret passed in @c
 * MSAppCenter:start:withServices: contains "target={targetToken}".
 *
 * For App Center backend the user identifier maximum length is 256 characters.
 *
 * AppCenter must be configured or started before this API can be used.
 */
+ (void)setUserId:(NSString *)userId;

/**
 * Set country code to use when building device properties.
 *
 * @param countryCode The two-letter ISO country code. @see https://www.iso.org/obp/ui/#search for more information.
 */
+ (void)setCountryCode:(NSString *)countryCode;

@end
