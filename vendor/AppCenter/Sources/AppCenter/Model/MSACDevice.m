// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDevice.h"
#import "MSACDeviceInternal.h"
#import "MSACWrapperSdkInternal.h"

@implementation MSACDevice

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];

  if (self.sdkName) {
    dict[kMSACSDKName] = self.sdkName;
  }
  if (self.sdkVersion) {
    dict[kMSACSDKVersion] = self.sdkVersion;
  }
  if (self.model) {
    dict[kMSACModel] = self.model;
  }
  if (self.oemName) {
    dict[kMSACOEMName] = self.oemName;
  }
  if (self.osName) {
    dict[kMSACACOSName] = self.osName;
  }
  if (self.osVersion) {
    dict[kMSACOSVersion] = self.osVersion;
  }
  if (self.osBuild) {
    dict[kMSACOSBuild] = self.osBuild;
  }
  if (self.osApiLevel) {
    dict[kMSACOSAPILevel] = self.osApiLevel;
  }
  if (self.locale) {
    dict[kMSACLocale] = self.locale;
  }
  if (self.timeZoneOffset) {
    dict[kMSACTimeZoneOffset] = self.timeZoneOffset;
  }
  if (self.screenSize) {
    dict[kMSACScreenSize] = self.screenSize;
  }
  if (self.appVersion) {
    dict[kMSACAppVersion] = self.appVersion;
  }
  if (self.carrierName) {
    dict[kMSACCarrierName] = self.carrierName;
  }
  if (self.carrierCountry) {
    dict[kMSACCarrierCountry] = self.carrierCountry;
  }
  if (self.appBuild) {
    dict[kMSACAppBuild] = self.appBuild;
  }
  if (self.appNamespace) {
    dict[kMSACAppNamespace] = self.appNamespace;
  }
  return dict;
}

- (BOOL)isValid {
  return [super isValid] && MSACLOG_VALIDATE_NOT_NIL(sdkName) && MSACLOG_VALIDATE_NOT_NIL(sdkVersion) && MSACLOG_VALIDATE_NOT_NIL(osName) &&
         MSACLOG_VALIDATE_NOT_NIL(osVersion) && MSACLOG_VALIDATE_NOT_NIL(locale) && MSACLOG_VALIDATE_NOT_NIL(timeZoneOffset) &&
         MSACLOG_VALIDATE_NOT_NIL(appVersion) && MSACLOG_VALIDATE_NOT_NIL(appBuild);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACDevice class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACDevice *device = (MSACDevice *)object;
  return ((!self.sdkName && !device.sdkName) || [self.sdkName isEqualToString:device.sdkName]) &&
         ((!self.sdkVersion && !device.sdkVersion) || [self.sdkVersion isEqualToString:device.sdkVersion]) &&
         ((!self.model && !device.model) || [self.model isEqualToString:device.model]) &&
         ((!self.oemName && !device.oemName) || [self.oemName isEqualToString:device.oemName]) &&
         ((!self.osName && !device.osName) || [self.osName isEqualToString:device.osName]) &&
         ((!self.osVersion && !device.osVersion) || [self.osVersion isEqualToString:device.osVersion]) &&
         ((!self.osBuild && !device.osBuild) || [self.osBuild isEqualToString:device.osBuild]) &&
         ((!self.osApiLevel && !device.osApiLevel) || [self.osApiLevel isEqualToNumber:device.osApiLevel]) &&
         ((!self.locale && !device.locale) || [self.locale isEqualToString:device.locale]) &&
         ((!self.timeZoneOffset && !device.timeZoneOffset) || [self.timeZoneOffset isEqualToNumber:device.timeZoneOffset]) &&
         ((!self.screenSize && !device.screenSize) || [self.screenSize isEqualToString:device.screenSize]) &&
         ((!self.appVersion && !device.appVersion) || [self.appVersion isEqualToString:device.appVersion]) &&
         ((!self.carrierName && !device.carrierName) || [self.carrierName isEqualToString:device.carrierName]) &&
         ((!self.carrierCountry && !device.carrierCountry) || [self.carrierCountry isEqualToString:device.carrierCountry]) &&
         ((!self.appBuild && !device.appBuild) || [self.appBuild isEqualToString:device.appBuild]) &&
         ((!self.appNamespace && !device.appNamespace) || [self.appNamespace isEqualToString:device.appNamespace]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _sdkName = [coder decodeObjectForKey:kMSACSDKName];
    _sdkVersion = [coder decodeObjectForKey:kMSACSDKVersion];
    _model = [coder decodeObjectForKey:kMSACModel];
    _oemName = [coder decodeObjectForKey:kMSACOEMName];
    _osName = [coder decodeObjectForKey:kMSACACOSName];
    _osVersion = [coder decodeObjectForKey:kMSACOSVersion];
    _osBuild = [coder decodeObjectForKey:kMSACOSBuild];
    _osApiLevel = [coder decodeObjectForKey:kMSACOSAPILevel];
    _locale = [coder decodeObjectForKey:kMSACLocale];
    _timeZoneOffset = [coder decodeObjectForKey:kMSACTimeZoneOffset];
    _screenSize = [coder decodeObjectForKey:kMSACScreenSize];
    _appVersion = [coder decodeObjectForKey:kMSACAppVersion];
    _carrierName = [coder decodeObjectForKey:kMSACCarrierName];
    _carrierCountry = [coder decodeObjectForKey:kMSACCarrierCountry];
    _appBuild = [coder decodeObjectForKey:kMSACAppBuild];
    _appNamespace = [coder decodeObjectForKey:kMSACAppNamespace];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.sdkName forKey:kMSACSDKName];
  [coder encodeObject:self.sdkVersion forKey:kMSACSDKVersion];
  [coder encodeObject:self.model forKey:kMSACModel];
  [coder encodeObject:self.oemName forKey:kMSACOEMName];
  [coder encodeObject:self.osName forKey:kMSACACOSName];
  [coder encodeObject:self.osVersion forKey:kMSACOSVersion];
  [coder encodeObject:self.osBuild forKey:kMSACOSBuild];
  [coder encodeObject:self.osApiLevel forKey:kMSACOSAPILevel];
  [coder encodeObject:self.locale forKey:kMSACLocale];
  [coder encodeObject:self.timeZoneOffset forKey:kMSACTimeZoneOffset];
  [coder encodeObject:self.screenSize forKey:kMSACScreenSize];
  [coder encodeObject:self.appVersion forKey:kMSACAppVersion];
  [coder encodeObject:self.carrierName forKey:kMSACCarrierName];
  [coder encodeObject:self.carrierCountry forKey:kMSACCarrierCountry];
  [coder encodeObject:self.appBuild forKey:kMSACAppBuild];
  [coder encodeObject:self.appNamespace forKey:kMSACAppNamespace];
}

@end
