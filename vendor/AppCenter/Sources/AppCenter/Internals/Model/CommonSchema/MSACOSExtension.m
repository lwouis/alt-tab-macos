// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACOSExtension.h"

@implementation MSACOSExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.ver) {
    dict[kMSACOSVer] = self.ver;
  }
  if (self.name) {
    dict[kMSACOSName] = self.name;
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
  if (![(NSObject *)object isKindOfClass:[MSACOSExtension class]]) {
    return NO;
  }
  MSACOSExtension *osExt = (MSACOSExtension *)object;
  return ((!self.ver && !osExt.ver) || [self.ver isEqualToString:osExt.ver]) &&
         ((!self.name && !osExt.name) || [self.name isEqualToString:osExt.name]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _ver = [coder decodeObjectForKey:kMSACOSVer];
    _name = [coder decodeObjectForKey:kMSACOSName];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.ver forKey:kMSACOSVer];
  [coder encodeObject:self.name forKey:kMSACOSName];
}

@end
