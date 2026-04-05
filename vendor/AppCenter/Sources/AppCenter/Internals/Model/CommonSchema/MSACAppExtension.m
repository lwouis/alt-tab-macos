// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppExtension.h"

@implementation MSACAppExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.appId) {
    dict[kMSACAppId] = self.appId;
  }
  if (self.ver) {
    dict[kMSACAppVer] = self.ver;
  }
  if (self.name) {
    dict[kMSACAppName] = self.name;
  }
  if (self.locale) {
    dict[kMSACAppLocale] = self.locale;
  }
  if (self.userId) {
    dict[kMSACAppUserId] = self.userId;
  }
  return dict.count == 0 ? nil : dict;
}

#pragma mark - MSACModel

- (BOOL)isValid {

  // All attributes are optional.
  return YES;
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACAppExtension class]]) {
    return NO;
  }
  MSACAppExtension *appExt = (MSACAppExtension *)object;
  return ((!self.appId && !appExt.appId) || [self.appId isEqualToString:appExt.appId]) &&
         ((!self.ver && !appExt.ver) || [self.ver isEqualToString:appExt.ver]) &&
         ((!self.name && !appExt.name) || [self.name isEqualToString:appExt.name]) &&
         ((!self.locale && !appExt.locale) || [self.locale isEqualToString:appExt.locale]) &&
         ((!self.userId && !appExt.userId) || [self.userId isEqualToString:appExt.userId]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _appId = [coder decodeObjectForKey:kMSACAppId];
    _ver = [coder decodeObjectForKey:kMSACAppVer];
    _name = [coder decodeObjectForKey:kMSACAppName];
    _locale = [coder decodeObjectForKey:kMSACAppLocale];
    _userId = [coder decodeObjectForKey:kMSACAppUserId];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.appId forKey:kMSACAppId];
  [coder encodeObject:self.ver forKey:kMSACAppVer];
  [coder encodeObject:self.name forKey:kMSACAppName];
  [coder encodeObject:self.locale forKey:kMSACAppLocale];
  [coder encodeObject:self.userId forKey:kMSACAppUserId];
}

@end
