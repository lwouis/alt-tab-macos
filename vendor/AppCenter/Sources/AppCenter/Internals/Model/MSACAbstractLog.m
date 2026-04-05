// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAbstractLogInternal.h"
#import "MSACAbstractLogPrivate.h"
#import "MSACAppExtension.h"
#import "MSACCSExtensions.h"
#import "MSACConstants+Internal.h"
#import "MSACDevice.h"
#import "MSACDeviceExtension.h"
#import "MSACDeviceInternal.h"
#import "MSACLocExtension.h"
#import "MSACNetExtension.h"
#import "MSACOSExtension.h"
#import "MSACProtocolExtension.h"
#import "MSACSDKExtension.h"
#import "MSACUserExtension.h"
#import "MSACUserIdContext.h"
#import "MSACUtility+Date.h"
#import "MSACUtility+StringFormatting.h"

/**
 * App namespace prefix for common schema.
 */
static NSString *const kMSACAppNamespacePrefix = @"I";

@implementation MSACAbstractLog

@synthesize type = _type;
@synthesize timestamp = _timestamp;
@synthesize sid = _sid;
@synthesize distributionGroupId = _distributionGroupId;
@synthesize userId = _userId;
@synthesize device = _device;
@synthesize tag = _tag;

- (instancetype)init {
  self = [super init];
  if (self) {
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];

  if (self.type) {
    dict[kMSACType] = self.type;
  }
  if (self.timestamp) {
    dict[kMSACTimestamp] = [MSACUtility dateToISO8601:self.timestamp];
  }
  if (self.sid) {
    dict[kMSACSId] = self.sid;
  }
  if (self.distributionGroupId) {
    dict[kMSACDistributionGroupId] = self.distributionGroupId;
  }
  if (self.userId) {
    dict[kMSACUserId] = self.userId;
  }
  if (self.device) {
    dict[kMSACDevice] = [self.device serializeToDictionary];
  }
  return dict;
}

- (BOOL)isValid {
  return MSACLOG_VALIDATE_NOT_NIL(type) && MSACLOG_VALIDATE_NOT_NIL(timestamp) &&
         MSACLOG_VALIDATE(device, self.device != nil && [self.device isValid]);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACAbstractLog class]]) {
    return NO;
  }
  MSACAbstractLog *log = (MSACAbstractLog *)object;
  return ((!self.tag && !log.tag) || [self.tag isEqual:log.tag]) && ((!self.type && !log.type) || [self.type isEqualToString:log.type]) &&
         ((!self.timestamp && !log.timestamp) || [self.timestamp isEqualToDate:log.timestamp]) &&
         ((!self.sid && !log.sid) || [self.sid isEqualToString:log.sid]) &&
         ((!self.distributionGroupId && !log.distributionGroupId) || [self.distributionGroupId isEqualToString:log.distributionGroupId]) &&
         ((!self.userId && !log.userId) || [self.userId isEqualToString:log.userId]) &&
         ((!self.device && !log.device) || [self.device isEqual:log.device]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _type = [coder decodeObjectForKey:kMSACType];
    _timestamp = [coder decodeObjectForKey:kMSACTimestamp];
    _sid = [coder decodeObjectForKey:kMSACSId];
    _distributionGroupId = [coder decodeObjectForKey:kMSACDistributionGroupId];
    _userId = [coder decodeObjectForKey:kMSACUserId];
    _device = [coder decodeObjectForKey:kMSACDevice];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.type forKey:kMSACType];
  [coder encodeObject:self.timestamp forKey:kMSACTimestamp];
  [coder encodeObject:self.sid forKey:kMSACSId];
  [coder encodeObject:self.distributionGroupId forKey:kMSACDistributionGroupId];
  [coder encodeObject:self.userId forKey:kMSACUserId];
  [coder encodeObject:self.device forKey:kMSACDevice];
}

#pragma mark - Utility

- (NSString *)serializeLogWithPrettyPrinting:(BOOL)prettyPrint {
  NSString *jsonString;
  NSJSONWritingOptions printOptions = prettyPrint ? NSJSONWritingPrettyPrinted : (NSJSONWritingOptions)0;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[self serializeToDictionary] options:printOptions error:nil];
  if (jsonData) {
    jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    jsonString = [jsonString stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
  }
  return jsonString;
}

#pragma mark - Transmission Target logic

- (NSSet *)transmissionTargetTokens {
  @synchronized(self) {
    return _transmissionTargetTokens;
  }
}

- (void)addTransmissionTargetToken:(NSString *)token {
  @synchronized(self) {
    if (self.transmissionTargetTokens == nil) {
      self.transmissionTargetTokens = [NSSet new];
    }
    NSMutableSet *mutableSet = [self.transmissionTargetTokens mutableCopy];
    [mutableSet addObject:token];
    self.transmissionTargetTokens = mutableSet;
  }
}

#pragma mark - MSACLogConversion

- (NSArray<MSACCommonSchemaLog *> *)toCommonSchemaLogsWithFlags:(MSACFlags)flags {
  NSMutableArray<MSACCommonSchemaLog *> *csLogs = [NSMutableArray new];
  for (NSString *token in self.transmissionTargetTokens) {
    MSACCommonSchemaLog *csLog = [self toCommonSchemaLogForTargetToken:token flags:(MSACFlags)flags];
    if (csLog) {
      [csLogs addObject:csLog];
    }
  }

  // Return nil if none are converted.
  return (csLogs.count > 0) ? csLogs : nil;
}

#pragma mark - Helper

- (MSACCommonSchemaLog *)toCommonSchemaLogForTargetToken:(NSString *)token flags:(MSACFlags)flags {
  MSACCommonSchemaLog *csLog = [MSACCommonSchemaLog new];
  csLog.transmissionTargetTokens = [NSSet setWithObject:token];
  csLog.ver = kMSACCSVerValue;
  csLog.timestamp = self.timestamp;

  // TODO popSample not supported at this time.

  // Calculate iKey based on the target token.
  csLog.iKey = [MSACUtility iKeyFromTargetToken:token];
  csLog.flags = flags;

  // TODO cV not supported at this time.

  // Setup extensions.
  csLog.ext = [MSACCSExtensions new];

  // Protocol extension.
  csLog.ext.protocolExt = [MSACProtocolExtension new];
  csLog.ext.protocolExt.devMake = self.device.oemName;
  csLog.ext.protocolExt.devModel = self.device.model;

  // User extension.
  csLog.ext.userExt = [MSACUserExtension new];
  csLog.ext.userExt.localId = [MSACUserIdContext prefixedUserIdFromUserId:self.userId];

  // FIXME Country code can be wrong if the locale doesn't correspond to the region in the setting (i.e.:fr_US). Convert user local to use
  // dash (-) as the separator as described in RFC 4646.  E.g., zh-Hans-CN.
  csLog.ext.userExt.locale = [self.device.locale stringByReplacingOccurrencesOfString:@"_" withString:@"-"];

  // OS extension.
  csLog.ext.osExt = [MSACOSExtension new];
  csLog.ext.osExt.name = self.device.osName;
  csLog.ext.osExt.ver = [self combineOsVersion:self.device.osVersion withBuild:self.device.osBuild];

  // App extension.
  csLog.ext.appExt = [MSACAppExtension new];
  csLog.ext.appExt.appId =
      [NSString stringWithFormat:@"%@%@%@", kMSACAppNamespacePrefix, kMSACCommonSchemaPrefixSeparator, self.device.appNamespace];
  csLog.ext.appExt.ver = self.device.appVersion;
  csLog.ext.appExt.locale = [[[NSBundle mainBundle] preferredLocalizations] firstObject];

  // Network extension.
  csLog.ext.netExt = [MSACNetExtension new];
  csLog.ext.netExt.provider = self.device.carrierName;

  // SDK extension.
  csLog.ext.sdkExt = [MSACSDKExtension new];
  csLog.ext.sdkExt.libVer = [self combineSDKLibVer:self.device.sdkName withVersion:self.device.sdkVersion];

  // Loc extension.
  csLog.ext.locExt = [MSACLocExtension new];
  csLog.ext.locExt.tz = [self convertTimeZoneOffsetToISO8601:[self.device.timeZoneOffset integerValue]];

  // Device extension.
  csLog.ext.deviceExt = [MSACDeviceExtension new];

  return csLog;
}

- (NSString *)combineOsVersion:(NSString *)version withBuild:(NSString *)build {
  NSString *combinedVersionAndBuild;
  if (version && version.length) {
    combinedVersionAndBuild = [NSString stringWithFormat:@"Version %@", version];
  }
  if (build && build.length) {
    combinedVersionAndBuild = [NSString stringWithFormat:@"%@ (Build %@)", combinedVersionAndBuild, build];
  }
  return combinedVersionAndBuild;
}

- (NSString *)combineSDKLibVer:(NSString *)name withVersion:(NSString *)version {
  NSString *combinedVersion;
  if (name && name.length && version && version.length) {
    combinedVersion = [NSString stringWithFormat:@"%@-%@", name, version];
  }
  return combinedVersion;
}

- (NSString *)convertTimeZoneOffsetToISO8601:(NSInteger)timeZoneOffset {
  NSInteger offsetInHour = timeZoneOffset / 60;
  NSInteger remainingMinutes = labs(timeZoneOffset) % 60;

  // This will look like this: +hhh:mm.
  return [NSString stringWithFormat:@"%+03ld:%02ld", (long)offsetInHour, (long)remainingMinutes];
}

@end
