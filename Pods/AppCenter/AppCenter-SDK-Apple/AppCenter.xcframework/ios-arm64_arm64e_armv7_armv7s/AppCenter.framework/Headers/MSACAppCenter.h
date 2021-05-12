// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#ifndef MSAC_APP_CENTER
#define MSAC_APP_CENTER

#if __has_include(<AppCenter/MSACConstants.h>)
#import <AppCenter/MSACConstants.h>
#else
#import "MSACConstants.h"
#endif

@class MSACWrapperSdk;

#if !TARGET_OS_TV
@class MSACCustomProperties;
#endif

NS_SWIFT_NAME(AppCenter)
@interface MSACAppCenter : NSObject

/**
 * Returns the singleton instance of MSACAppCenter.
 */
+ (instancetype)sharedInstance;

/**
 * Configure the SDK with an application secret.
 *
 * @param appSecret A unique and secret key used to identify the application.
 *
 * @discussion This may be called only once per application process lifetime.
 */
+ (void)configureWithAppSecret:(NSString *)appSecret NS_SWIFT_NAME(configure(withAppSecret:));

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
+ (void)start:(NSString *)appSecret withServices:(NSArray<Class> *)services NS_SWIFT_NAME(start(withAppSecret:services:));

/**
 * Start the SDK with an array of services.
 *
 * @param services  Array of services to start.
 *
 * @discussion This may be called only once per application process lifetime.
 */
+ (void)startWithServices:(NSArray<Class> *)services NS_SWIFT_NAME(start(services:));

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
+ (void)startFromLibraryWithServices:(NSArray<Class> *)services NS_SWIFT_NAME(startFromLibrary(services:));

/**
 * The flag indicates whether the SDK has already been configured or not.
 */
@property(class, atomic, readonly, getter=isConfigured) BOOL configured;

/**
 * The flag indicates whether app is running in App Center Test Cloud.
 */
@property(class, atomic, readonly, getter=isRunningInAppCenterTestCloud) BOOL runningInAppCenterTestCloud;

/**
 * The flag indicates whether or not the SDK was enabled as a whole
 *
 * The state is persisted in the device's storage across application launches.
 */
@property(class, nonatomic, getter=isEnabled, setter=setEnabled:) BOOL enabled NS_SWIFT_NAME(enabled);

/**
 * The SDK's log level.
 */
@property(class, nonatomic) MSACLogLevel logLevel;

/**
 * Base URL to use for backend communication.
 */
@property(class, nonatomic) NSString *logUrl;

/**
 * Set log handler.
 */
@property(class, nonatomic) MSACLogHandler logHandler;

/**
 * Set wrapper SDK information to use when building device properties. This is intended in case you are building a SDK that uses the App
 * Center SDK under the hood, e.g. our Xamarin SDK or ReactNative SDk.
 */
@property(class, nonatomic) MSACWrapperSdk *wrapperSdk;

#if !TARGET_OS_TV
/**
 * Set the custom properties.
 *
 * @param customProperties Custom properties object.
 */
+ (void)setCustomProperties:(MSACCustomProperties *)customProperties;
#endif

/**
 * Check whether the application delegate forwarder is enabled or not.
 *
 * @discussion The application delegate forwarder forwards messages that target your application delegate methods via swizzling to the SDK.
 * It simplifies the SDK integration but may not be suitable to any situations. For
 * instance it should be disabled if you or one of your third party SDK is doing message forwarding on the application delegate. Message
 * forwarding usually implies the implementation of @see NSObject#forwardingTargetForSelector: or @see NSObject#forwardInvocation: methods.
 * To disable the application delegate forwarder just add the `AppCenterAppDelegateForwarderEnabled` tag to your Info .plist file and set it
 * to `0`. Then you will have to forward any application delegate needed by the SDK manually.
 */
@property(class, readonly, nonatomic, getter=isAppDelegateForwarderEnabled) BOOL appDelegateForwarderEnabled;

/**
 * Unique installation identifier.
 *
 */
@property(class, readonly, nonatomic) NSUUID *installId;

/**
 * Detect if a debugger is attached to the app process. This is only invoked once on app startup and can not detect
 * if the debugger is being attached during runtime!
 *
 */
@property(class, readonly, nonatomic, getter=isDebuggerAttached) BOOL debuggerAttached;

/**
 * Current version of AppCenter SDK.
 *
 */
@property(class, readonly, nonatomic) NSString *sdkVersion;

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
 * @discussion Set the user identifier for logs sent for the default target token when the secret passed in @c
 * MSACAppCenter:start:withServices: contains "target={targetToken}".
 *
 * For App Center backend the user identifier maximum length is 256 characters.
 *
 * AppCenter must be configured or started before this API can be used.
 */
@property(class, nonatomic) NSString *userId;

/**
 * Set country code to use when building device properties.
 *
 * @see https://www.iso.org/obp/ui/#search for more information.
 */
@property(class, nonatomic) NSString *countryCode;

@end

#endif
