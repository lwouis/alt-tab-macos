// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCSExtensions.h"
#import "MSACAbstractLogInternal.h"
#import "MSACAppExtension.h"
#import "MSACDeviceExtension.h"
#import "MSACLocExtension.h"
#import "MSACMetadataExtension.h"
#import "MSACNetExtension.h"
#import "MSACOSExtension.h"
#import "MSACProtocolExtension.h"
#import "MSACSDKExtension.h"
#import "MSACUserExtension.h"

@implementation MSACCSExtensions

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.metadataExt) {
    dict[kMSACCSMetadataExt] = [self.metadataExt serializeToDictionary];
  }
  if (self.protocolExt) {
    dict[kMSACCSProtocolExt] = [self.protocolExt serializeToDictionary];
  }
  if (self.userExt) {
    dict[kMSACCSUserExt] = [self.userExt serializeToDictionary];
  }
  if (self.deviceExt) {
    dict[kMSACCSDeviceExt] = [self.deviceExt serializeToDictionary];
  }
  if (self.osExt) {
    dict[kMSACCSOSExt] = [self.osExt serializeToDictionary];
  }
  if (self.appExt) {
    dict[kMSACCSAppExt] = [self.appExt serializeToDictionary];
  }
  if (self.netExt) {
    dict[kMSACCSNetExt] = [self.netExt serializeToDictionary];
  }
  if (self.sdkExt) {
    dict[kMSACCSSDKExt] = [self.sdkExt serializeToDictionary];
  }
  if (self.locExt) {
    dict[kMSACCSLocExt] = [self.locExt serializeToDictionary];
  }
  return dict;
}

#pragma mark - MSACModel

- (BOOL)isValid {
#define MSACLOG_VALIDATE_OPTIONAL_OBJECT(fieldName) MSACLOG_VALIDATE(fieldName, self.fieldName == nil || [self.fieldName isValid])
  return MSACLOG_VALIDATE_OPTIONAL_OBJECT(metadataExt) && MSACLOG_VALIDATE_OPTIONAL_OBJECT(protocolExt) &&
         MSACLOG_VALIDATE_OPTIONAL_OBJECT(userExt) && MSACLOG_VALIDATE_OPTIONAL_OBJECT(deviceExt) &&
         MSACLOG_VALIDATE_OPTIONAL_OBJECT(osExt) && MSACLOG_VALIDATE_OPTIONAL_OBJECT(appExt) && MSACLOG_VALIDATE_OPTIONAL_OBJECT(netExt) &&
         MSACLOG_VALIDATE_OPTIONAL_OBJECT(sdkExt) && MSACLOG_VALIDATE_OPTIONAL_OBJECT(locExt);
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACCSExtensions class]]) {
    return NO;
  }
  MSACCSExtensions *csExt = (MSACCSExtensions *)object;
  return ((!self.protocolExt && !csExt.protocolExt) || [self.protocolExt isEqual:csExt.protocolExt]) &&
         ((!self.metadataExt && !csExt.metadataExt) || [self.metadataExt isEqual:csExt.metadataExt]) &&
         ((!self.userExt && !csExt.userExt) || [self.userExt isEqual:csExt.userExt]) &&
         ((!self.deviceExt && !csExt.deviceExt) || [self.deviceExt isEqual:csExt.deviceExt]) &&
         ((!self.osExt && !csExt.osExt) || [self.osExt isEqual:csExt.osExt]) &&
         ((!self.appExt && !csExt.appExt) || [self.appExt isEqual:csExt.appExt]) &&
         ((!self.netExt && !csExt.netExt) || [self.netExt isEqual:csExt.netExt]) &&
         ((!self.sdkExt && !csExt.sdkExt) || [self.sdkExt isEqual:csExt.sdkExt]) &&
         ((!self.locExt && !csExt.locExt) || [self.locExt isEqual:csExt.locExt]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _metadataExt = [coder decodeObjectForKey:kMSACCSMetadataExt];
    _protocolExt = [coder decodeObjectForKey:kMSACCSProtocolExt];
    _userExt = [coder decodeObjectForKey:kMSACCSUserExt];
    _deviceExt = [coder decodeObjectForKey:kMSACCSDeviceExt];
    _osExt = [coder decodeObjectForKey:kMSACCSOSExt];
    _appExt = [coder decodeObjectForKey:kMSACCSAppExt];
    _netExt = [coder decodeObjectForKey:kMSACCSNetExt];
    _sdkExt = [coder decodeObjectForKey:kMSACCSSDKExt];
    _locExt = [coder decodeObjectForKey:kMSACCSLocExt];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.metadataExt forKey:kMSACCSMetadataExt];
  [coder encodeObject:self.protocolExt forKey:kMSACCSProtocolExt];
  [coder encodeObject:self.userExt forKey:kMSACCSUserExt];
  [coder encodeObject:self.deviceExt forKey:kMSACCSDeviceExt];
  [coder encodeObject:self.osExt forKey:kMSACCSOSExt];
  [coder encodeObject:self.appExt forKey:kMSACCSAppExt];
  [coder encodeObject:self.netExt forKey:kMSACCSNetExt];
  [coder encodeObject:self.sdkExt forKey:kMSACCSSDKExt];
  [coder encodeObject:self.locExt forKey:kMSACCSLocExt];
}

@end
