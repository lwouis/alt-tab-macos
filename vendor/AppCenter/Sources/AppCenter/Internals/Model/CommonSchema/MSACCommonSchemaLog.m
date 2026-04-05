// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCommonSchemaLog.h"
#import "MSACCSData.h"
#import "MSACCSExtensions.h"
#import "MSACModel.h"
#import "MSACOrderedDictionary.h"
#import "MSACUtility+Date.h"

@implementation MSACCommonSchemaLog

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {

  // ORDER MATTERS: Make sure ver, name, timestamp, popSample, iKey and flags appear first in part A.
  // No call to super here, it already contains everything needed for CS JSON serialization.
  NSMutableDictionary *dict = [MSACOrderedDictionary new];
  if (self.ver) {
    dict[kMSACCSVer] = self.ver;
  }
  if (self.name) {
    dict[kMSACCSName] = self.name;
  }

  // Timestamp already exists in the parent implementation but the serialized key is different.
  if (self.timestamp) {
    dict[kMSACCSTime] = [MSACUtility dateToISO8601:self.timestamp];
  }

  // TODO: Not supporting popSample and cV today. When added, popSample needs to be ordered between timestamp and iKey.
  if (self.iKey) {
    dict[kMSACCSIKey] = self.iKey;
  }
  if (self.flags) {
    dict[kMSACCSFlags] = @(self.flags);
  }
  if (self.ext) {
    dict[kMSACCSExt] = [self.ext serializeToDictionary];
  }
  if (self.data) {
    dict[kMSACCSData] = [self.data serializeToDictionary];
  }
  return dict;
}

#pragma mark - MSACModel

- (BOOL)isValid {

  // Do not call [super isValid] here as CS logs don't require the same validation as AC logs except for timestamp.
  return MSACLOG_VALIDATE_NOT_NIL(timestamp) && MSACLOG_VALIDATE_NOT_NIL(ver) && MSACLOG_VALIDATE_NOT_NIL(name);
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACCommonSchemaLog class]] || ![super isEqual:object]) {
    return NO;
  }

  MSACCommonSchemaLog *csLog = (MSACCommonSchemaLog *)object;
  return ((!self.ver && !csLog.ver) || [self.ver isEqualToString:csLog.ver]) &&
         ((!self.name && !csLog.name) || [self.name isEqualToString:csLog.name]) && self.popSample == csLog.popSample &&
         ((!self.iKey && !csLog.iKey) || [self.iKey isEqualToString:csLog.iKey]) && self.flags == csLog.flags &&
         ((!self.cV && !csLog.cV) || [self.cV isEqualToString:csLog.cV]) && ((!self.ext && !csLog.ext) || [self.ext isEqual:csLog.ext]) &&
         ((!self.data && !csLog.data) || [self.data isEqual:csLog.data]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super initWithCoder:coder])) {
    _ver = [coder decodeObjectForKey:kMSACCSVer];
    _name = [coder decodeObjectForKey:kMSACCSName];
    _popSample = [coder decodeDoubleForKey:kMSACCSPopSample];
    _iKey = [coder decodeObjectForKey:kMSACCSIKey];
    _flags = [coder decodeInt64ForKey:kMSACCSFlags];
    _cV = [coder decodeObjectForKey:kMSACCSCV];
    _ext = [coder decodeObjectForKey:kMSACCSExt];
    _data = [coder decodeObjectForKey:kMSACCSData];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.ver forKey:kMSACCSVer];
  [coder encodeObject:self.name forKey:kMSACCSName];
  [coder encodeDouble:self.popSample forKey:kMSACCSPopSample];
  [coder encodeObject:self.iKey forKey:kMSACCSIKey];
  [coder encodeInt64:self.flags forKey:kMSACCSFlags];
  [coder encodeObject:self.cV forKey:kMSACCSCV];
  [coder encodeObject:self.ext forKey:kMSACCSExt];
  [coder encodeObject:self.data forKey:kMSACCSData];
}

@end
