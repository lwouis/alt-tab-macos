// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDeviceTracker.h"
#import "MSACAppCenterUserDefaults.h"
#import "MSACConstants+Internal.h"
#import "MSACDeviceHistoryInfo.h"
#import "MSACDeviceTrackerPrivate.h"
#import "MSACUtility+Application.h"
#import "MSACUtility+Date.h"
#import "MSACUtility.h"
#import "MSACWrapperSdkInternal.h"

static NSUInteger const kMSACMaxDevicesHistoryCount = 5;

@interface MSACDeviceTracker ()

// We need a private setter for the device to avoid the warning that is related to direct access of ivars.
@property(nonatomic) MSACDevice *device;

@end

@implementation MSACDeviceTracker : NSObject

static BOOL needRefresh = YES;
static MSACWrapperSdk *wrapperSdkInformation = nil;
static NSString *overriddenCountryCode = nil;

/**
 * Singleton.
 */
static dispatch_once_t onceToken;
static MSACDeviceTracker *sharedInstance = nil;

#pragma mark - Initialisation

+ (instancetype)sharedInstance {
  dispatch_once(&onceToken, ^{
    sharedInstance = [[MSACDeviceTracker alloc] init];
  });
  return sharedInstance;
}

+ (void)resetSharedInstance {
  onceToken = 0;
  sharedInstance = nil;

  // Reset state of global variables.
  // FIXME: move it to shared instance.
  needRefresh = YES;
  wrapperSdkInformation = nil;
  overriddenCountryCode = nil;
}

- (instancetype)init {
  if ((self = [super init])) {

    // Restore past sessions from NSUserDefaults.
    NSData *devices = [MSAC_APP_CENTER_USER_DEFAULTS objectForKey:kMSACPastDevicesKey];
    if (devices != nil) {
      NSArray *arrayFromData = (NSArray *)[[MSACUtility unarchiveKeyedData:devices] mutableCopy];

      // If array is not nil, create a mutable version.
      if (arrayFromData != nil) {
        _deviceHistory = [NSMutableArray arrayWithArray:arrayFromData];
      }
    }

    // Create new array and create device info in case we don't have any from disk.
    if (_deviceHistory == nil) {
      _deviceHistory = [NSMutableArray<MSACDeviceHistoryInfo *> new];
    }

    // This will instantiate the device property to make sure we have a history.
    [self device];
  }
  return self;
}

- (void)setWrapperSdk:(MSACWrapperSdk *)wrapperSdk {
  @synchronized(self) {
    wrapperSdkInformation = wrapperSdk;
    needRefresh = YES;

    // Replace the last device without wrapperSdk in the UserDefaults with an updated info.
    [self.deviceHistory removeLastObject];
    [self device];
  }
}

- (void)setCountryCode:(NSString *)countryCode {
  @synchronized(self) {
    overriddenCountryCode = countryCode;
    needRefresh = YES;
  }
}

- (NSString *)countryCode {
  @synchronized(self) {
    return overriddenCountryCode;
  }
}

- (MSACWrapperSdk *)wrapperSdk {
  @synchronized(self) {
    return wrapperSdkInformation;
  }
}

+ (void)refreshDeviceNextTime {
  @synchronized([MSACDeviceTracker sharedInstance]) {
    needRefresh = YES;
  }
}

/**
 *  Get the current device log.
 */
- (MSACDevice *)device {
  @synchronized(self) {

    // Lazy creation in case the property hasn't been set yet.
    if (!_device || needRefresh) {

      // Get new device info.
      _device = [self updatedDevice];

      // Create new MSACDeviceHistoryInfo.
      MSACDeviceHistoryInfo *deviceHistoryInfo = [[MSACDeviceHistoryInfo alloc] initWithTimestamp:[NSDate date] andDevice:_device];

      // Insert new MSACDeviceHistoryInfo at the proper index to keep self.deviceHistory sorted.
      NSUInteger newIndex = [self.deviceHistory indexOfObject:deviceHistoryInfo
                                                inSortedRange:(NSRange){0, [self.deviceHistory count]}
                                                      options:NSBinarySearchingInsertionIndex
                                              usingComparator:^(MSACDeviceHistoryInfo *a, MSACDeviceHistoryInfo *b) {
                                                return [a.timestamp compare:b.timestamp];
                                              }];
      [self.deviceHistory insertObject:deviceHistoryInfo atIndex:newIndex];

      // Remove first (the oldest) item if reached max limit.
      if ([self.deviceHistory count] > kMSACMaxDevicesHistoryCount) {
        [self.deviceHistory removeObjectAtIndex:0];
      }

      // Persist the device history in NSData format.
      [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.deviceHistory] forKey:kMSACPastDevicesKey];
    }
    return _device;
  }
}

/**
 * Refresh device properties.
 */
- (MSACDevice *)updatedDevice {
  @synchronized(self) {
    MSACDevice *newDevice = [MSACDevice new];
#if TARGET_OS_IOS
    CTTelephonyNetworkInfo *telephonyNetworkInfo = [CTTelephonyNetworkInfo new];
    CTCarrier *carrier;

    // The CTTelephonyNetworkInfo.serviceSubscriberCellularProviders method crash because of an issue in iOS 12.0
    // It was fixed in iOS 12.1
    if (@available(iOS 12.1, *)) {
      NSDictionary<NSString *, CTCarrier *> *carriers = [telephonyNetworkInfo serviceSubscriberCellularProviders];
      carrier = [self firstCarrier:carriers];
    } else if (@available(iOS 12, *)) {
      NSDictionary<NSString *, CTCarrier *> *carriers = [telephonyNetworkInfo valueForKey:@"serviceSubscriberCellularProvider"];
      carrier = [self firstCarrier:carriers];
    }

    // Use the old API as fallback if new one doesn't work.
    if (carrier == nil) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      carrier = [telephonyNetworkInfo subscriberCellularProvider];
#pragma clang diagnostic pop
    }
#endif

    // Collect device properties.
    newDevice.sdkName = [MSACUtility sdkName];
    newDevice.sdkVersion = [MSACUtility sdkVersion];
    newDevice.model = [self deviceModel];
    newDevice.oemName = kMSACDeviceManufacturer;
#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
    newDevice.osName = [self osName];
#else
    newDevice.osName = [self osName:MSAC_DEVICE];
#endif
#if TARGET_OS_OSX
    newDevice.osVersion = [self osVersion];
#else
    newDevice.osVersion = [self osVersion:MSAC_DEVICE];
#endif
    newDevice.osBuild = [self osBuild];
    newDevice.locale = [self locale:MSAC_LOCALE];
    newDevice.timeZoneOffset = [self timeZoneOffset:[NSTimeZone localTimeZone]];
    newDevice.screenSize = [self screenSize];
    newDevice.appVersion = [self appVersion:MSAC_APP_MAIN_BUNDLE];
#if TARGET_OS_IOS
    newDevice.carrierCountry = [self carrierCountry:carrier] ?: overriddenCountryCode;
    newDevice.carrierName = [self carrierName:carrier];
#else

    // Carrier information is not available on macOS/tvOS, but if we have an override country code, use it.
    newDevice.carrierCountry = overriddenCountryCode;
    newDevice.carrierName = nil;
#endif
    newDevice.appBuild = [self appBuild:MSAC_APP_MAIN_BUNDLE];
    newDevice.appNamespace = [self appNamespace:MSAC_APP_MAIN_BUNDLE];

    // Add wrapper SDK information
    [self refreshWrapperSdk:newDevice];

    // Make sure we set the flag to indicate we don't need to update our device info.
    needRefresh = NO;

    // Return new device.
    return newDevice;
  }
}

/**
 *  Refresh wrapper SDK properties.
 */
- (void)refreshWrapperSdk:(MSACDevice *)device {
  if (wrapperSdkInformation) {
    device.wrapperSdkVersion = wrapperSdkInformation.wrapperSdkVersion;
    device.wrapperSdkName = wrapperSdkInformation.wrapperSdkName;
    device.wrapperRuntimeVersion = wrapperSdkInformation.wrapperRuntimeVersion;
    device.liveUpdateReleaseLabel = wrapperSdkInformation.liveUpdateReleaseLabel;
    device.liveUpdateDeploymentKey = wrapperSdkInformation.liveUpdateDeploymentKey;
    device.liveUpdatePackageHash = wrapperSdkInformation.liveUpdatePackageHash;
  }
}

- (MSACDevice *)deviceForTimestamp:(NSDate *)timestamp {
  if (!timestamp || self.deviceHistory.count == 0) {

    // Return a new device in case we don't have a device in our history or timestamp is nil.
    return [self device];
  } else {

    // This implements a binary search with complexity O(log n).
    MSACDeviceHistoryInfo *find = [[MSACDeviceHistoryInfo alloc] initWithTimestamp:timestamp andDevice:nil];
    NSUInteger index = [self.deviceHistory indexOfObject:find
                                           inSortedRange:NSMakeRange(0, self.deviceHistory.count)
                                                 options:NSBinarySearchingFirstEqual | NSBinarySearchingInsertionIndex
                                         usingComparator:^(MSACDeviceHistoryInfo *a, MSACDeviceHistoryInfo *b) {
                                           return [a.timestamp compare:b.timestamp];
                                         }];

    /*
     * All timestamps are larger.
     * For now, the SDK picks up the oldest which is closer to the device info at the crash time.
     */
    if (index == 0) {
      return self.deviceHistory[0].device;
    }

    // All timestamps are smaller.
    else if (index == self.deviceHistory.count) {
      return [self.deviceHistory lastObject].device;
    }

    // [index - 1] should be the right index for the timestamp.
    else {
      return self.deviceHistory[index - 1].device;
    }
  }
}

- (void)clearDevices {
  @synchronized(self) {

    // Clear information about the entire history, except for the current device.
    if (self.deviceHistory.count > 1) {
      [self.deviceHistory removeObjectsInRange:NSMakeRange(0, self.deviceHistory.count - 1)];
    }

    // Clear persistence, but keep the latest information about the device.
    [MSAC_APP_CENTER_USER_DEFAULTS setObject:[MSACUtility archiveKeyedData:self.deviceHistory] forKey:kMSACPastDevicesKey];
  }
}

#pragma mark - Helpers

- (NSString *)deviceModel {
  size_t size;
#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
  const char *name = "hw.model";
#else
  const char *name = "hw.machine";
#endif
  sysctlbyname(name, NULL, &size, NULL, 0);
  char *answer = (char *)malloc(size);
  if (answer == NULL) {
    return @"Unknown";
  }
  sysctlbyname(name, answer, &size, NULL, 0);
  NSString *model = [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];
  free(answer);
  return model ? model : @"Unknown";
}

#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
- (NSString *)osName {
  return @"macOS";
}
#else
- (NSString *)osName:(UIDevice *)device {
  return device.systemName;
}
#endif

#if TARGET_OS_OSX
- (NSString *)osVersion {
  NSString *osVersion = nil;

  if (@available(macOS 10.10, *)) {
    NSOperatingSystemVersion osSystemVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)osSystemVersion.majorVersion, (long)osSystemVersion.minorVersion,
                                           (long)osSystemVersion.patchVersion];
  } else {
    SInt32 major, minor, bugfix;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"
    OSErr err1 = Gestalt(gestaltSystemVersionMajor, &major);
    OSErr err2 = Gestalt(gestaltSystemVersionMinor, &minor);
    OSErr err3 = Gestalt(gestaltSystemVersionBugFix, &bugfix);
    if ((!err1) && (!err2) && (!err3)) {
      osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)major, (long)minor, (long)bugfix];
    }
#pragma clang diagnostic pop
  }
  return osVersion;
}
#else
- (NSString *)osVersion:(UIDevice *)device {
  return device.systemVersion;
}
#endif

- (NSString *)osBuild {
  size_t size;
  sysctlbyname("kern.osversion", NULL, &size, NULL, 0);
  char *answer = (char *)malloc(size);
  if (answer == NULL) {
    return @"Unknown";
  }
  sysctlbyname("kern.osversion", answer, &size, NULL, 0);
  NSString *osBuild = [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];
  free(answer);
  return osBuild ? osBuild : @"Unknown";
}

- (NSString *)locale:(NSLocale *)currentLocale {

  /*
   * [currentLocale objectForKey:NSLocaleIdentifier] will return an alternate language if a language set in system is not supported by
   * applications. If system language is set to en_US but an application doesn't support en_US, for example, the OS will return the next
   * application supported language in Preferred Language Order list unless there is only one language in the list. The method will return
   * the first language in the list to prevent from the above scenario.
   *
   * In addition to that:
   * 1. preferred language returns "-" instead of "_" as a delimiter of language code and country code, the method will concatenate language
   * code and country code with "_" and return it.
   * 2. some languages can be set without country code so region code can be returned in this case.
   * 3. some langugaes have script code which differentiate languages. E.g. zh-Hans and zh-Hant. This is a possible scenario in Apple
   * platforms that a locale can be zh_CN for Traditional Chinese. The method will return zh-Hant_CN in this case to make sure system
   * language is Traditional Chinese even though region is set to China.
   */
  NSLocale *preferredLanguage = [[NSLocale alloc] initWithLocaleIdentifier:[NSLocale preferredLanguages][0]];
  NSString *languageCode = [preferredLanguage objectForKey:NSLocaleLanguageCode];
  NSString *scriptCode = [preferredLanguage objectForKey:NSLocaleScriptCode];
  NSString *countryCode = [preferredLanguage objectForKey:NSLocaleCountryCode];
  NSString *locale =
      [NSString stringWithFormat:@"%@%@_%@", languageCode, (scriptCode ? [NSString stringWithFormat:@"-%@", scriptCode] : @""),
                                 countryCode ?: [currentLocale objectForKey:NSLocaleCountryCode]];
  return locale;
}

- (NSNumber *)timeZoneOffset:(NSTimeZone *)timeZone {
  return @([timeZone secondsFromGMT] / 60);
}

- (NSString *)screenSize {
#if TARGET_OS_OSX

  // Report screen resolution as shown in display settings ('Looks like' field in scaling tab).
  NSSize screenSize = [NSScreen mainScreen].frame.size;
  return [NSString stringWithFormat:@"%dx%d", (int)screenSize.width, (int)screenSize.height];
#elif TARGET_OS_MACCATALYST

  // macOS API is not directly avaliable on Mac Catalyst.
  NSObject *screen = [NSClassFromString(@"NSScreen") valueForKey:@"mainScreen"];
  if (screen == nil) {
    CGSize screenSize = [UIScreen mainScreen].nativeBounds.size;
    return [NSString stringWithFormat:@"%dx%d", (int)screenSize.width, (int)screenSize.height];
  }
  SEL selector = NSSelectorFromString(@"frame");
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[screen class] instanceMethodSignatureForSelector:selector]];
  [invocation setSelector:selector];
  [invocation setTarget:screen];
  [invocation invoke];
  CGRect frame;
  [invocation getReturnValue:&frame];
  return [NSString stringWithFormat:@"%dx%d", (int)frame.size.width, (int)frame.size.height];
#else
  CGFloat scale = [UIScreen mainScreen].scale;
  CGSize screenSize = [UIScreen mainScreen].bounds.size;
  return [NSString stringWithFormat:@"%dx%d", (int)(screenSize.height * scale), (int)(screenSize.width * scale)];
#endif
}

#if TARGET_OS_IOS
- (NSString *)carrierName:(CTCarrier *)carrier {
  return [self isValidCarrierName:carrier.carrierName] ? carrier.carrierName : nil;
}

- (NSString *)carrierCountry:(CTCarrier *)carrier {
  return ([carrier.isoCountryCode length] > 0) ? carrier.isoCountryCode : nil;
}

- (BOOL)isValidCarrierName:(NSString *)carrier {
  return [carrier length] > 0 && [@"carrier" caseInsensitiveCompare:carrier] != NSOrderedSame;
}

- (CTCarrier *)firstCarrier:(NSDictionary<NSString *, CTCarrier *> *)carriers {
  for (NSString *key in carriers) {
    return carriers[key];
  }
  return nil;
}
#endif

- (NSString *)appVersion:(NSBundle *)appBundle {
  return [appBundle infoDictionary][@"CFBundleShortVersionString"];
}

- (NSString *)appBuild:(NSBundle *)appBundle {
  return [appBundle infoDictionary][@"CFBundleVersion"];
}

- (NSString *)appNamespace:(NSBundle *)appBundle {
  return [appBundle bundleIdentifier];
}

@end
