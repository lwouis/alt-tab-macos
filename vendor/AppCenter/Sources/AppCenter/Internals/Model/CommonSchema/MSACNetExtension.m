// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACNetExtension.h"

@implementation MSACNetExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict;
  if (self.provider) {
    dict = [NSMutableDictionary new];
    dict[kMSACNetProvider] = self.provider;
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
  if (![(NSObject *)object isKindOfClass:[MSACNetExtension class]]) {
    return NO;
  }
  MSACNetExtension *netExt = (MSACNetExtension *)object;
  return ((!self.provider && !netExt.provider) || [self.provider isEqualToString:netExt.provider]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _provider = [coder decodeObjectForKey:kMSACNetProvider];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.provider forKey:kMSACNetProvider];
}

@end
