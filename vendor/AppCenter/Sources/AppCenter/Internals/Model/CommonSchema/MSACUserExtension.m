// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACUserExtension.h"

@implementation MSACUserExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.localId) {
    dict[kMSACUserLocalId] = self.localId;
  }
  if (self.locale) {
    dict[kMSACUserLocale] = self.locale;
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
  if (![(NSObject *)object isKindOfClass:[MSACUserExtension class]]) {
    return NO;
  }
  MSACUserExtension *userExt = (MSACUserExtension *)object;
  return ((!self.localId && !userExt.localId) || [self.localId isEqualToString:userExt.localId]) &&
         ((!self.locale && !userExt.locale) || [self.locale isEqualToString:userExt.locale]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _localId = [coder decodeObjectForKey:kMSACUserLocalId];
    _locale = [coder decodeObjectForKey:kMSACUserLocale];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.localId forKey:kMSACUserLocalId];
  [coder encodeObject:self.locale forKey:kMSACUserLocale];
}

@end
