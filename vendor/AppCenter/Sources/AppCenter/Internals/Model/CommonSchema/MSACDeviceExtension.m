// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDeviceExtension.h"

@implementation MSACDeviceExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict;
  if (self.localId) {
    dict = [NSMutableDictionary new];
    dict[kMSACDeviceLocalId] = self.localId;
  }
  return dict;
}

#pragma mark - MSACModel

- (BOOL)isValid {

  // All attributes are optional.
  return YES;
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACDeviceExtension class]]) {
    return NO;
  }
  MSACDeviceExtension *deviceExt = (MSACDeviceExtension *)object;
  return (!self.localId && !deviceExt.localId) || [self.localId isEqualToString:deviceExt.localId];
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _localId = [coder decodeObjectForKey:kMSACDeviceLocalId];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.localId forKey:kMSACDeviceLocalId];
}

@end
