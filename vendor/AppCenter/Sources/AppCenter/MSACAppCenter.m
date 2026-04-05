// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACAppCenterIngestion.h"
#import "MSACAppCenterInternal.h"
#import "MSACAppCenterPrivate.h"
#import "MSACAppDelegateForwarder.h"
#import "MSACChannelGroupDefault.h"
#import "MSACChannelGroupDefaultPrivate.h"
#import "MSACChannelUnitConfiguration.h"
#import "MSACDependencyConfiguration.h"
#import "MSACDeviceHistoryInfo.h"
#import "MSACDeviceTrackerPrivate.h"
#import "MSACHttpClient.h"
#import "MSACLogWithProperties.h"
#import "MSACLoggerInternal.h"
#import "MSACOneCollectorChannelDelegate.h"
#import "MSACSessionContext.h"
#import "MSACStartServiceLog.h"
#import "MSACUserIdContext.h"
#import "MSACUtility+StringFormatting.h"

#if !TARGET_OS_TV
#import "MSACCustomPropertiesInternal.h"
#import "MSACCustomPropertiesLog.h"
#endif

/**
 * Singleton.
 */
static MSACAppCenter *sharedInstance = nil;
static dispatch_once_t onceToken;

/**
 * Base URL for HTTP Ingestion backend API calls.
 */
static NSString *const kMSACAppCenterBaseUrl = @"https://in.appcenter.ms";

/**
 * Service name for initialization.
 */
static NSString *const kMSACServiceName = @"AppCenter";

/**
 * The group Id for storage.
 */
static NSString *const kMSACGroupId = @"AppCenter";

/**
 * The minimum storage size, limited by SQLite.
 * 24 KiB to be able to send the default logs (start service, start session, push installation).
 */
static const long kMSACMinUpperSizeLimitInBytes = 24 * 1024;

@implementation MSACAppCenter

@synthesize installId = _installId;

@synthesize logUrl = _logUrl;

+ (instancetype)sharedInstance {
  dispatch_once(&onceToken, ^{
    if (sharedInstance == nil) {
      sharedInstance = [[MSACAppCenter alloc] init];
    }
  });
  return sharedInstance;
}

#pragma mark - public

+ (void)configureWithAppSecret:(NSString *)appSecret {

  // 'appSecret' is actually a secret string
  NSString *appSecretOnly = [MSACUtility appSecretFrom:appSecret];
  NSString *transmissionTargetToken = [MSACUtility transmissionTargetTokenFrom:appSecret];
  [[MSACAppCenter sharedInstance] configureWithAppSecret:appSecretOnly transmissionTargetToken:transmissionTargetToken fromApplication:YES];
}

+ (void)configure {
  [[MSACAppCenter sharedInstance] configureWithAppSecret:nil transmissionTargetToken:nil fromApplication:YES];
}

+ (void)start:(NSString *)appSecret withServices:(NSArray<Class> *)services {

  // 'appSecret' is actually a secret string
  [[MSACAppCenter sharedInstance] start:appSecret withServices:services fromApplication:YES];
}

+ (void)startWithServices:(NSArray<Class> *)services {
  [[MSACAppCenter sharedInstance] start:nil withServices:services fromApplication:YES];
}

+ (void)startService:(Class)service {
  if (!service) {
    return;
  }
  [[MSACAppCenter sharedInstance] startServices:@[ service ]
                                  withAppSecret:[[MSACAppCenter sharedInstance] appSecret]
                        transmissionTargetToken:[[MSACAppCenter sharedInstance] defaultTransmissionTargetToken]
                                fromApplication:YES];
}

+ (void)startFromLibraryWithServices:(NSArray<Class> *)services {
  [[MSACAppCenter sharedInstance] start:nil withServices:services fromApplication:NO];
}

+ (BOOL)isConfigured {
  return [MSACAppCenter sharedInstance].sdkConfigured && [MSACAppCenter sharedInstance].configuredFromApplication;
}

+ (BOOL)isRunningInAppCenterTestCloud {
  NSDictionary *environmentVariables = [[NSProcessInfo processInfo] environment];
  NSString *runningInAppCenter = environmentVariables[kMSACRunningInAppCenter];
  if ([runningInAppCenter isEqualToString:kMSACTrueEnvironmentString]) {
    return YES;
  }
  return NO;
}

+ (void)setLogUrl:(NSString *)logUrl {
  [[MSACAppCenter sharedInstance] setLogUrl:logUrl];
}

+ (void)setEnabled:(BOOL)isEnabled {
  [[MSACAppCenter sharedInstance] setEnabled:isEnabled];
}

/**
 * Checks if SDK is enabled and initialized.
 *
 * @discussion This method is different from the instance one and in addition checks canBeUsed.
 *
 * @return `YES` if SDK is enabled and initialized, `NO` otherwise
 */
+ (BOOL)isEnabled {
  @synchronized([MSACAppCenter sharedInstance]) {
    if ([[MSACAppCenter sharedInstance] canBeUsed]) {
      return [[MSACAppCenter sharedInstance] isEnabled];
    }
  }
  return NO;
}

+ (void)setNetworkRequestsAllowed:(BOOL)isAllowed {
  [[MSACAppCenter sharedInstance] setNetworkRequestsAllowed:isAllowed];
}

/**
 * Checks if SDK can send network requests.
 *
 * @return `YES` if network requests are allowed, `NO` otherwise
 */
+ (BOOL)isNetworkRequestsAllowed {
  @synchronized([MSACAppCenter sharedInstance]) {
    return [[MSACAppCenter sharedInstance] isNetworkRequestsAllowed];
  }
}

+ (BOOL)isAppDelegateForwarderEnabled {
  return [MSACAppDelegateForwarder sharedInstance].enabled;
}

+ (NSUUID *)installId {
  return [[MSACAppCenter sharedInstance] installId];
}

+ (MSACLogLevel)logLevel {
  return MSACLogger.currentLogLevel;
}

+ (void)setLogLevel:(MSACLogLevel)logLevel {
  MSACLogger.currentLogLevel = logLevel;

  // The logger is not set at the time of swizzling but now may be a good time to flush the traces.
  [MSACDelegateForwarder flushTraceBuffer];
}

+ (void)setLogHandler:(MSACLogHandler)logHandler {
  [MSACLogger setLogHandler:logHandler];
}

+ (void)setWrapperSdk:(MSACWrapperSdk *)wrapperSdk {
  [[MSACDeviceTracker sharedInstance] setWrapperSdk:wrapperSdk];
}

+ (NSString *)countryCode {
  return [MSACDeviceTracker sharedInstance].countryCode;
}

+ (MSACWrapperSdk *)wrapperSdk {
  return [MSACDeviceTracker sharedInstance].wrapperSdk;
}

+ (NSString *)userId {
  return [MSACUserIdContext sharedInstance].userId;
}

+ (MSACLogHandler)logHandler {
  return MSACLogger.logHandler;
}

#if !TARGET_OS_TV
+ (void)setCustomProperties:(MSACCustomProperties *)customProperties {
  [[MSACAppCenter sharedInstance] setCustomProperties:customProperties];
}
#endif

/**
 * Check if the debugger is attached
 *
 * Taken from
 * https://github.com/plausiblelabs/plcrashreporter/blob/2dd862ce049e6f43feb355308dfc710f3af54c4d/Source/Crash%20Demo/main.m#L96
 *
 * @return `YES` if the debugger is attached to the current process, `NO` otherwise
 */
+ (BOOL)isDebuggerAttached {
  static BOOL debuggerIsAttached = NO;

  static dispatch_once_t debuggerPredicate;
  dispatch_once(&debuggerPredicate, ^{
    struct kinfo_proc info;
    size_t info_size = sizeof(info);
    int name[4];

    name[0] = CTL_KERN;
    name[1] = KERN_PROC;
    name[2] = KERN_PROC_PID;
    name[3] = getpid();

    if (sysctl(name, 4, &info, &info_size, NULL, 0) == -1) {
      NSLog(@"[MSACCrashes] ERROR: Checking for a running debugger via sysctl() "
            @"failed.");
      debuggerIsAttached = false;
    }

    if (!debuggerIsAttached && (info.kp_proc.p_flag & P_TRACED) != 0) {
      debuggerIsAttached = true;
    }
  });

  return debuggerIsAttached;
}

+ (NSString *)sdkVersion {
  return [MSACUtility sdkVersion];
}

+ (NSString *)logTag {
  return kMSACServiceName;
}

+ (NSString *)groupId {
  return kMSACGroupId;
}

+ (void)setMaxStorageSize:(long)sizeInBytes completionHandler:(void (^)(BOOL))completionHandler {
  [[MSACAppCenter sharedInstance] setMaxStorageSize:sizeInBytes completionHandler:completionHandler];
}

+ (void)setUserId:(NSString *)userId {
  [[MSACAppCenter sharedInstance] setUserId:userId];
}

+ (void)setCountryCode:(NSString *)countryCode {
  [[MSACDeviceTracker sharedInstance] setCountryCode:countryCode];
}

#pragma mark - private

- (instancetype)init {
  if ((self = [super init])) {
    _services = [NSMutableArray new];
    _enabledStateUpdating = NO;
    NSDictionary *changedKeys = @{
      @"MSAppCenterChannelStartTimer" : MSACPrefixKeyFrom(@"MSChannelStartTimer"),
      // [MSACChannelUnitDefault oldestPendingLogTimestampKey]
      @"MSAppCenterPastDevices" : @"pastDevicesKey",
      // [MSACDeviceTracker init],
      // [MSACDeviceTracker device],
      // [MSACDeviceTracker clearDevices]
      @"MSAppCenterInstallId" : @"MSInstallId",
      // [MSACAppCenter installId]
      @"MSAppCenterAppCenterIsEnabled" : @"MSAppCenterIsEnabled",
      // [MSACAppCenter isEnabled]
      @"MSAppCenterEncryptionKeyMetadata" : @"MSEncryptionKeyMetadata",
      // [MSACEncrypter getCurrentKeyTag],
      // [MSACEncrypter rotateToNewKeyTag]
      @"MSAppCenterSessionIdHistory" : @"SessionIdHistory",
      // [MSACSessionContext init],
      // [MSACSessionContext setSessionId],
      // [MSACSessionContext clearSessionHistoryAndKeepCurrentSession]
      @"MSAppCenterUserIdHistory" : @"UserIdHistory"
      // [MSACUserIdContext init],
      // [MSACUserIdContext setUserId],
      // [MSACUserIdContext clearUserIdHistory]
    };
    [MSAC_APP_CENTER_USER_DEFAULTS migrateKeys:changedKeys forService:kMSACServiceName];
  }
  [MSACUtility addMigrationClasses:@{
    @"MSDeviceHistoryInfo" : MSACDeviceHistoryInfo.self,
    @"MSDevice" : MSACDevice.self,
    @"MSStartServiceLog" : MSACStartServiceLog.self,
    @"MSSessionHistoryInfo" : MSACSessionHistoryInfo.self,
    @"MSUserIdHistoryInfo" : MSACUserIdHistoryInfo.self,
    @"MSLogWithProperties" : MSACLogWithProperties.self,
    @"MSLogContainer" : MSACLogContainer.self,
    @"MSWrapperSdk" : MSACWrapperSdk.self,
    @"MSAbstractLog" : MSACAbstractLog.self,
  }];
#if !TARGET_OS_TV
  [MSACUtility addMigrationClasses:@{@"MSCustomProperties" : MSACCustomProperties.self}];
#endif
  return self;
}

/**
 * Configuring without an app secret is valid. If that is the case, the app secret will not be set.
 */
- (BOOL)configureWithAppSecret:(NSString *)appSecret
       transmissionTargetToken:(NSString *)transmissionTargetToken
               fromApplication:(BOOL)fromApplication {
  @synchronized(self) {
    BOOL success = false;
    if (self.configuredFromApplication && fromApplication) {
      MSACLogAssert([MSACAppCenter logTag], @"App Center SDK has already been configured.");
    } else {
      if (!self.appSecret) {
        self.appSecret = appSecret;

        // Initialize session context.
        // FIXME: It would be better to have obvious way to initialize session context instead of calling setSessionId.
        [[MSACSessionContext sharedInstance] setSessionId:nil];
      }
      if (!self.defaultTransmissionTargetToken) {
        self.defaultTransmissionTargetToken = transmissionTargetToken;
      }

      /*
       * Instantiate MSACUserIdContext as early as possible to prevent Crashes from using older userId when a newer version of app removes
       * setUserId call from older version of app. MSACUserIdContext will handle this one in intializer so we need to make sure
       * MSACUserIdContext is initialized before Crashes service processes logs.
       */
      [MSACUserIdContext sharedInstance];

      // Init the main pipeline.
      [self initializeChannelGroup];
      [self applyPipelineEnabledState:self.isEnabled];
      self.sdkConfigured = YES;
      self.configuredFromApplication = self.configuredFromApplication || fromApplication;

      /*
       * If the log level hasn't been customized before and we are not running in an app store environment, we set the default log level to
       * MSACLogLevelWarning.
       */
      if ((![MSACLogger isUserDefinedLogLevel]) && ([MSACUtility currentAppEnvironment] == MSACEnvironmentOther)) {
        [MSACAppCenter setLogLevel:MSACLogLevelWarning];
      }
      success = true;
    }
    if (success) {
      MSACLogInfo([MSACAppCenter logTag], @"App Center SDK configured %@successfully.", fromApplication ? @"" : @"from a library ");
    } else {
      MSACLogAssert([MSACAppCenter logTag], @"App Center SDK configuration %@failed.", fromApplication ? @"" : @"from a library ");
    }
    return success;
  }
}

- (void)start:(NSString *)secretString withServices:(NSArray<Class> *)services fromApplication:(BOOL)fromApplication {
  NSString *appSecret = [MSACUtility appSecretFrom:secretString];
  NSString *transmissionTargetToken = [MSACUtility transmissionTargetTokenFrom:secretString];
  BOOL configured = [self configureWithAppSecret:appSecret transmissionTargetToken:transmissionTargetToken fromApplication:fromApplication];
  if (configured && services) {
    [self startServices:services withAppSecret:appSecret transmissionTargetToken:transmissionTargetToken fromApplication:fromApplication];
  }
}

- (void)startServices:(NSArray<Class> *)services
              withAppSecret:(NSString *)appSecret
    transmissionTargetToken:(NSString *)transmissionTargetToken
            fromApplication:(BOOL)fromApplication {
  if (!self.sdkConfigured || !services) {
    return;
  }
  NSArray *sortedServices = [self sortServices:services];
  MSACLogVerbose([MSACAppCenter logTag], @"Start services %@ from %@", [sortedServices componentsJoinedByString:@", "],
                 (fromApplication ? @"an application" : @"a library"));
  NSMutableArray<NSString *> *servicesNames = [NSMutableArray arrayWithCapacity:sortedServices.count];
  for (Class service in sortedServices) {
    if ([self startService:service
                      withAppSecret:appSecret
            transmissionTargetToken:transmissionTargetToken
                    fromApplication:fromApplication]) {
      [servicesNames addObject:[service serviceName]];
    }
  }
  if ([servicesNames count] > 0) {
    if (fromApplication) {
      [self sendStartServiceLog:servicesNames];
    }
  } else {
    MSACLogDebug([MSACAppCenter logTag], @"No services have been started.");
  }
}

/**
 * Sort services in descending order to make sure the service with the highest priority gets initialized first. This is intended to make
 * sure Crashes gets initialized first.
 *
 * @param services An array of services.
 */
- (NSArray *)sortServices:(NSArray<Class> *)services {
  if (services && services.count > 1) {
    return [services sortedArrayUsingComparator:^NSComparisonResult(id clazzA, id clazzB) {
#pragma clang diagnostic push

// Ignore "Unknown warning group '-Wobjc-messaging-id'" for old XCode
#pragma clang diagnostic ignored "-Wunknown-pragmas"
#pragma clang diagnostic ignored "-Wunknown-warning-option"

// Ignore "Messaging unqualified id" for XCode 10
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
      id<MSACServiceInternal> serviceA = [clazzA sharedInstance];
      id<MSACServiceInternal> serviceB = [clazzB sharedInstance];
#pragma clang diagnostic pop
      if (serviceA.initializationPriority < serviceB.initializationPriority) {
        return NSOrderedDescending;
      } else {
        return NSOrderedAscending;
      }
    }];
  } else {
    return services;
  }
}

- (BOOL)startService:(Class)clazz
              withAppSecret:(NSString *)appSecret
    transmissionTargetToken:(NSString *)transmissionTargetToken
            fromApplication:(BOOL)fromApplication {
  @synchronized(self) {

    // Check if clazz is valid class.
    if (![clazz conformsToProtocol:@protocol(MSACServiceCommon)]) {
      MSACLogError([MSACAppCenter logTag], @"Cannot start service %@. Provided value is nil or invalid.", clazz);
      return NO;
    }

    // Check if App Center is not configured to start service.
    if (!self.sdkConfigured || (!self.configuredFromApplication && fromApplication)) {
      MSACLogError([MSACAppCenter logTag], @"App Center has not been configured so it couldn't start the service.");
      return NO;
    }
    id<MSACServiceInternal> service = [clazz sharedInstance];
    if (service.isAvailable && fromApplication && service.isStartedFromApplication) {

      // Service already works, we shouldn't send log with this service name
      return NO;
    }
    if (service.isAppSecretRequired && ![appSecret length]) {

      // Service requires an app secret but none is provided.
      MSACLogError([MSACAppCenter logTag],
                   @"Cannot start service %@. App Center was started without app secret, but the service requires it.", clazz);
      return NO;
    }

    // Check if service should be disabled.
    if ([self shouldDisable:[clazz serviceName]]) {
      MSACLogDebug([MSACAppCenter logTag], @"Environment variable to disable service has been set; not starting service %@", clazz);
      return NO;
    }

    if (!service.isAvailable) {

      // Set appCenterDelegate.
      [self.services addObject:service];

      // Start service with channel group.
      [service startWithChannelGroup:self.channelGroup
                           appSecret:appSecret
             transmissionTargetToken:transmissionTargetToken
                     fromApplication:fromApplication];

      // Disable service if AppCenter is disabled.
      if ([clazz isEnabled] && !self.isEnabled) {
        self.enabledStateUpdating = YES;
        [clazz setEnabled:NO];
        self.enabledStateUpdating = NO;
      }
    } else if (fromApplication) {
      [service updateConfigurationWithAppSecret:appSecret transmissionTargetToken:transmissionTargetToken];
    }

    // Service started.
    return YES;
  }
}

- (NSString *)logUrl {
  return _logUrl;
}

+ (NSString *)logUrl {
  return [MSACAppCenter sharedInstance].logUrl;
}

- (void)setLogUrl:(NSString *)logUrl {
  @synchronized(self) {
    _logUrl = logUrl;
    id<MSACChannelGroupProtocol> localChannelGroup = self.channelGroup;
    if (localChannelGroup) {
      if (self.appSecret) {
        MSACLogInfo([MSACAppCenter logTag], @"The log url of App Center endpoint was changed to %@", self.logUrl);
        [localChannelGroup setLogUrl:logUrl];
      } else {
        MSACLogInfo([MSACAppCenter logTag], @"The log url of One Collector endpoint was changed to %@", self.logUrl);
        [self.oneCollectorChannelDelegate setLogUrl:logUrl];
      }
    }
  }
}

- (void)setMaxStorageSize:(long)sizeInBytes completionHandler:(void (^)(BOOL))completionHandler
#if defined(__IPHONE_15_0)
NS_SWIFT_DISABLE_ASYNC
#endif
{

  // Check if sizeInBytes is greater than minimum size.
  if (sizeInBytes < kMSACMinUpperSizeLimitInBytes) {
    if (completionHandler) {
      completionHandler(NO);
    }
    MSACLogWarning([MSACAppCenter logTag], @"Cannot set storage size to %ld bytes, minimum value is %ld bytes", sizeInBytes,
                   kMSACMinUpperSizeLimitInBytes);
    return;
  }

  // Change the max storage size.
  BOOL setMaxSizeFailed = NO;
  @synchronized(self) {
    if (self.setMaxStorageSizeHasBeenCalled) {
      MSACLogWarning([MSACAppCenter logTag], @"setMaxStorageSize:completionHandler: may only be called once per app launch");
      setMaxSizeFailed = YES;
    } else {
      self.setMaxStorageSizeHasBeenCalled = YES;
      if (self.configuredFromApplication) {
        MSACLogWarning([MSACAppCenter logTag], @"Unable to set storage size after the application has configured App Center");
        setMaxSizeFailed = YES;
      } else {
        self.requestedMaxStorageSizeInBytes = @(sizeInBytes);
        self.maxStorageSizeCompletionHandler = completionHandler;
        if (self.channelGroup) {
          [self.channelGroup setMaxStorageSize:sizeInBytes completionHandler:self.maxStorageSizeCompletionHandler];
        }
      }
    }
  }
  if (setMaxSizeFailed && completionHandler) {
    completionHandler(NO);
  }
}

- (void)setUserId:(NSString *)userId {
  if (!self.configuredFromApplication) {
    MSACLogError([MSACAppCenter logTag], @"AppCenter must be configured from application, libraries cannot call setUserId.");
    return;
  }
  if (!self.appSecret && !self.defaultTransmissionTargetToken) {
    MSACLogError([MSACAppCenter logTag], @"AppCenter must be configured with a secret from application to call setUserId.");
    return;
  }
  if (userId) {
    if (self.appSecret && ![MSACUserIdContext isUserIdValidForAppCenter:userId]) {
      return;
    }
    if (self.defaultTransmissionTargetToken && ![MSACUserIdContext isUserIdValidForOneCollector:userId]) {
      return;
    }
  }
  [[MSACUserIdContext sharedInstance] setUserId:userId];
}

#if !TARGET_OS_TV
- (void)setCustomProperties:(MSACCustomProperties *)customProperties {
  NSDictionary<NSString *, NSObject *> *propertiesCopy = [customProperties propertiesImmutableCopy];
  if (!customProperties || (propertiesCopy.count == 0)) {
    MSACLogError([MSACAppCenter logTag], @"Custom properties may not be null or empty");
    return;
  }
  [self sendCustomPropertiesLog:propertiesCopy];
}
#endif

- (void)setNetworkRequestsAllowed:(BOOL)isAllowed {
  @synchronized(self) {
    MSACLogInfo([MSACAppCenter logTag], @"App Center SDK network requests are %@.", isAllowed ? @"allowed" : @"forbidden");

    // Persist the network permission status.
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:@(isAllowed) forKey:kMSACAppCenterNetworkRequestsAllowedKey];
    if ([self canBeUsed]) {
      if (isAllowed) {
        [self.channelGroup resumeWithIdentifyingObject:self.channelGroup];
      } else {
        [self.channelGroup pauseWithIdentifyingObject:self.channelGroup];
      }
    }
  }
}

- (BOOL)isNetworkRequestsAllowed {

  /*
   * Get isAllowed value from persistence.
   * No need to cache the value in a property, user settings already have their cache mechanism.
   */
  NSNumber *isAllowed = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACAppCenterNetworkRequestsAllowedKey];

  // Return the persisted value otherwise it's enabled by default.
  return isAllowed != nil ? [isAllowed boolValue] : YES;
}

- (void)setEnabled:(BOOL)isEnabled {
  @synchronized(self) {
    if (![self canBeUsed]) {
      return;
    }
    self.enabledStateUpdating = YES;
    if ([self isEnabled] != isEnabled) {

      // Persist the enabled status.
      [MSAC_APP_CENTER_USER_DEFAULTS setObject:@(isEnabled) forKey:kMSACAppCenterIsEnabledKey];

      // Enable/disable pipeline.
      [self applyPipelineEnabledState:isEnabled];
    }

    // Propagate enable/disable on all services.
    for (id<MSACServiceInternal> service in self.services) {
      [[service class] setEnabled:isEnabled];
    }
    self.enabledStateUpdating = NO;
    MSACLogInfo([MSACAppCenter logTag], @"App Center SDK %@.", isEnabled ? @"enabled" : @"disabled");
  }
}

- (BOOL)isEnabled {

  /*
   * Get isEnabled value from persistence.
   * No need to cache the value in a property, user settings already have their cache mechanism.
   */
  NSNumber *isEnabledNumber = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACAppCenterIsEnabledKey];

  // Return the persisted value otherwise it's enabled by default.
  return (isEnabledNumber) ? [isEnabledNumber boolValue] : YES;
}

- (void)applyPipelineEnabledState:(BOOL)isEnabled {

  // Remove all notification handlers.
  [MSAC_NOTIFICATION_CENTER removeObserver:self];

  // Hookup to application life-cycle events.
  if (isEnabled) {
#if !TARGET_OS_OSX
    [MSAC_NOTIFICATION_CENTER addObserver:self
                                 selector:@selector(applicationDidEnterBackground)
                                     name:UIApplicationDidEnterBackgroundNotification
                                   object:nil];
    [MSAC_NOTIFICATION_CENTER addObserver:self
                                 selector:@selector(applicationWillEnterForeground)
                                     name:UIApplicationWillEnterForegroundNotification
                                   object:nil];
#endif
  } else {

    // Clean session, device and userId history in case we are disabled.
    [[MSACDeviceTracker sharedInstance] clearDevices];
    [[MSACSessionContext sharedInstance] clearSessionHistoryAndKeepCurrentSession:NO];
    [[MSACUserIdContext sharedInstance] clearUserIdHistory];
  }

  @synchronized(self) {

    // Propagate to channel group.
    [self.channelGroup setEnabled:isEnabled andDeleteDataOnDisabled:YES];

    // Send started services.
    if (self.startedServiceNames && isEnabled) {
      [self sendStartServiceLog:self.startedServiceNames];
      self.startedServiceNames = nil;
    }
  }
}

- (void)initializeChannelGroup {
  @synchronized(self) {

    // Construct channel group.
    if (!self.oneCollectorChannelDelegate) {
      self.oneCollectorChannelDelegate = [[MSACOneCollectorChannelDelegate alloc] initWithHttpClient:[MSACHttpClient new]
                                                                                           installId:self.installId
                                                                                             baseUrl:self.appSecret ? nil : self.logUrl];
    }
    if (!self.channelGroup) {
      id<MSACHttpClientProtocol> httpClient = [MSACDependencyConfiguration httpClient];
      if (!httpClient) {
        httpClient = [MSACHttpClient new];
      }
      self.channelGroup = [[MSACChannelGroupDefault alloc] initWithHttpClient:httpClient
                                                                    installId:self.installId
                                                                       logUrl:self.logUrl ?: kMSACAppCenterBaseUrl];
      [self.channelGroup addDelegate:self.oneCollectorChannelDelegate];
      if (self.requestedMaxStorageSizeInBytes) {
        long storageSize = [self.requestedMaxStorageSizeInBytes longValue];
        [self.channelGroup setMaxStorageSize:storageSize completionHandler:self.maxStorageSizeCompletionHandler];
      }
    }
    [self.channelGroup setAppSecret:self.appSecret];

    // Initialize a channel unit for start service logs.
    self.channelUnit =
        self.channelUnit
            ?: [self.channelGroup addChannelUnitWithConfiguration:[[MSACChannelUnitConfiguration alloc]
                                                                      initDefaultConfigurationWithGroupId:[MSACAppCenter groupId]]];
  }
}

- (NSString *)appSecret {
  return _appSecret;
}

- (NSUUID *)installId {
  @synchronized(self) {
    if (!_installId) {

      // Check if install Id has already been persisted.
      NSString *savedInstallId = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACInstallIdKey];
      if (savedInstallId) {
        _installId = MSAC_UUID_FROM_STRING(savedInstallId);
      }

      // Create a new random install Id if persistence failed.
      if (!_installId) {
        _installId = [NSUUID UUID];

        // Persist the install Id string.
        [MSAC_APP_CENTER_USER_DEFAULTS setObject:[_installId UUIDString] forKey:kMSACInstallIdKey];
      }
    }
    return _installId;
  }
}

- (BOOL)canBeUsed {
  BOOL canBeUsed = self.sdkConfigured;
  if (!canBeUsed) {
    MSACLogError([MSACAppCenter logTag], @"App Center SDK hasn't been configured. You need to call [MSACAppCenter start:YOUR_APP_SECRET "
                                         @"withServices:LIST_OF_SERVICES] first.");
  }
  return canBeUsed;
}

- (void)sendStartServiceLog:(NSArray<NSString *> *)servicesNames {
  @synchronized(self) {
    if (self.isEnabled) {
      MSACStartServiceLog *serviceLog = [MSACStartServiceLog new];
      serviceLog.services = servicesNames;
      [self.channelUnit enqueueItem:serviceLog flags:MSACFlagsDefault];
    } else {
      if (self.startedServiceNames == nil) {
        self.startedServiceNames = [NSMutableArray new];
      }
      [self.startedServiceNames addObjectsFromArray:servicesNames];
    }
  }
}

#if !TARGET_OS_TV
- (void)sendCustomPropertiesLog:(NSDictionary<NSString *, NSObject *> *)properties {
  MSACCustomPropertiesLog *customPropertiesLog = [MSACCustomPropertiesLog new];
  customPropertiesLog.properties = properties;
  [self.channelUnit enqueueItem:customPropertiesLog flags:MSACFlagsDefault];
}
#endif

+ (void)resetSharedInstance {
  onceToken = 0; // resets the once_token so dispatch_once will run again
  sharedInstance = nil;
}

#pragma mark - Application life cycle

#if !TARGET_OS_OSX
/**
 *  The application will go to the foreground.
 */
- (void)applicationWillEnterForeground {
  [self.channelGroup resumeWithIdentifyingObject:self];
}

/**
 *  The application will go to the background.
 */
- (void)applicationDidEnterBackground {
  [self.channelGroup pauseWithIdentifyingObject:self];
}
#endif

#pragma mark - Disable services for test cloud

/**
 * Determines whether a service should be disabled.
 *
 * @param serviceName The service name to consider for disabling.
 *
 * @return YES if the service should be disabled.
 */
- (BOOL)shouldDisable:(NSString *)serviceName {
  NSDictionary *environmentVariables = [[NSProcessInfo processInfo] environment];
  NSString *disabledServices = environmentVariables[kMSACDisableVariable];
  if (!disabledServices) {
    return NO;
  }
  NSMutableArray *disabledServicesList = [NSMutableArray arrayWithArray:[disabledServices componentsSeparatedByString:@","]];

  // Trim whitespace characters.
  for (NSUInteger i = 0; i < [disabledServicesList count]; ++i) {
    NSString *service = disabledServicesList[i];
    service = [service stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    disabledServicesList[i] = service;
  }
  return [disabledServicesList containsObject:serviceName] || [disabledServicesList containsObject:kMSACDisableAll];
}

@end
