// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppDelegateForwarder.h"
#import "MSACCustomApplicationDelegate.h"
#import "MSACUtility+Application.h"

// Original selectors with special handling.
static NSString *const kMSACOpenURLSourceApplicationAnnotation = @"application:openURL:sourceApplication:annotation:";
static NSString *const kMSACOpenURLOptions = @"application:openURL:options:";

// Singleton instance.
static MSACAppDelegateForwarder *sharedInstance = nil;
static dispatch_once_t swizzlingOnceToken;

@implementation MSACAppDelegateForwarder

+ (void)load {

  /*
   * The application starts querying its delegate for its implementation as soon as it is set then may never query again. It means that if
   * the application delegate doesn't implement an optional method of the `UIApplicationDelegate` protocol at that time then that method may
   * never be called even if added later via swizzling. This is why the application delegate swizzling should happen at the time it is set
   * to the application object.
   */
  [[MSACAppDelegateForwarder sharedInstance] setEnabledFromPlistForKey:kMSACAppDelegateForwarderEnabledKey];
}

- (instancetype)init {
  if ((self = [super init])) {
#if !TARGET_OS_OSX && !TARGET_OS_MACCATALYST
    self.deprecatedSelectors = @{kMSACOpenURLOptions : kMSACOpenURLSourceApplicationAnnotation};
#endif
  }
  return self;
}

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [self new];
  });
  return sharedInstance;
}

+ (void)resetSharedInstance {
  sharedInstance = [self new];
}

- (Class)originalClassForSetDelegate {
  return [MSACApplication class];
}

- (dispatch_once_t *)swizzlingOnceToken {
  return &swizzlingOnceToken;
}

#pragma mark - Custom Application

- (void)custom_setDelegate:(id<MSACApplicationDelegate>)delegate {

  // Swizzle only once.
  static dispatch_once_t delegateSwizzleOnceToken;
  dispatch_once(&delegateSwizzleOnceToken, ^{
    // Swizzle the delegate object before it's actually set.
    [[MSACAppDelegateForwarder sharedInstance] swizzleOriginalDelegate:delegate];
  });

  // Forward to the original `setDelegate:` implementation.
  IMP originalImp = [MSACAppDelegateForwarder sharedInstance].originalSetDelegateImp;
  if (originalImp) {
    ((void (*)(id, SEL, id<MSACApplicationDelegate>))originalImp)(self, _cmd, delegate);
  }
}

#pragma mark - Custom UIApplicationDelegate

#if !TARGET_OS_OSX && !TARGET_OS_MACCATALYST

/*
 * Those methods will never get called but their implementation will be used by swizzling. Those implementations will run within the
 * delegate context. Meaning that `self` will point to the original app delegate and not this forwarder.
 */
- (BOOL)custom_application:(UIApplication *)application
                   openURL:(NSURL *)url
         sourceApplication:(nullable NSString *)sourceApplication
                annotation:(id)annotation {
  BOOL result = NO;
  IMP originalImp = NULL;

  // Forward to the original delegate.
  [[MSACAppDelegateForwarder sharedInstance].originalImplementations[NSStringFromSelector(_cmd)] getValue:&originalImp];
  if (originalImp) {
    result = ((BOOL(*)(id, SEL, UIApplication *, NSURL *, NSString *, id))originalImp)(self, _cmd, application, url, sourceApplication,
                                                                                       annotation);
  }

  // Forward to custom delegates.
  return [[MSACAppDelegateForwarder sharedInstance] application:application
                                                        openURL:url
                                              sourceApplication:sourceApplication
                                                     annotation:annotation
                                                  returnedValue:result];
}

- (BOOL)custom_application:(UIApplication *)application
                   openURL:(nonnull NSURL *)url
                   options:(nonnull NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
  BOOL result = NO;
  IMP originalImp = NULL;

  // Forward to the original delegate.
  [[MSACAppDelegateForwarder sharedInstance].originalImplementations[NSStringFromSelector(_cmd)] getValue:&originalImp];
  if (originalImp) {
    result = ((BOOL(*)(id, SEL, UIApplication *, NSURL *, NSDictionary<UIApplicationOpenURLOptionsKey, id> *))originalImp)(
        self, _cmd, application, url, options);
  }

  // Forward to custom delegates.
  return [[MSACAppDelegateForwarder sharedInstance] application:application openURL:url options:options returnedValue:result];
}
#endif

@end
