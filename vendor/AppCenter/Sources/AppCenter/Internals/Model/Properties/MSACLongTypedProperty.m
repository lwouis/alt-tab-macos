// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACLongTypedProperty.h"

@implementation MSACLongTypedProperty

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACLongTypedPropertyType;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _value = [coder decodeInt64ForKey:kMSACTypedPropertyValue];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeInt64:self.value forKey:kMSACTypedPropertyValue];
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  dict[kMSACTypedPropertyValue] = @(self.value);
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACLongTypedProperty class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACLongTypedProperty *property = (MSACLongTypedProperty *)object;
  return (self.value == property.value);
}

@end
