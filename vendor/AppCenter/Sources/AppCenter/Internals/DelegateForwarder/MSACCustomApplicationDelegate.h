// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppDelegateUtil.h"
#import "MSACCustomDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Custom delegate matching @c UIApplicationDelegate.
 *
 * @discussion Delegates here are using swizzling. Any delegate that can be registered through the notification center should not be
 * registered through swizzling. Due to the early registration of swizzling on the original app delegate each custom delegate must sign up
 * for selectors to swizzle within the `load` method of a category over the @c MSACAppDelegateForwarder class.
 */
@protocol MSACCustomApplicationDelegate <MSACCustomDelegate>

@optional

#if !TARGET_OS_OSX && !TARGET_OS_MACCATALYST

/**
 * Asks the delegate to open a resource specified by a URL, and provides a dictionary of launch options.
 *
 * @param application The singleton app object.
 * @param url The URL resource to open. This resource can be a network resource or a file.
 * @param sourceApplication The bundle ID of the app that is requesting your app to open the URL (url).
 * @param annotation A Property list supplied by the source app to communicate information to the receiving app.
 * @param returnedValue Value returned by the original delegate implementation.
 *
 * @return `YES` if the delegate successfully handled the request or `NO` if the attempt to open the URL resource failed.
 */
- (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)url
    sourceApplication:(nullable NSString *)sourceApplication
           annotation:(id)annotation
        returnedValue:(BOOL)returnedValue;

/**
 * Asks the delegate to open a resource specified by a URL, and provides a dictionary of launch options.
 *
 * @param application The singleton app object.
 * @param url The URL resource to open. This resource can be a network resource or a file.
 * @param options A dictionary of URL handling options. For information about the possible keys in this dictionary and how to handle them,
 * @see UIApplicationOpenURLOptionsKey. By default, the value of this parameter is an empty dictionary.
 * @param returnedValue Value returned by the original delegate implementation.
 *
 * @return `YES` if the delegate successfully handled the request or `NO` if the attempt to open the URL resource failed.
 */
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
      returnedValue:(BOOL)returnedValue;

#endif

@end

NS_ASSUME_NONNULL_END
