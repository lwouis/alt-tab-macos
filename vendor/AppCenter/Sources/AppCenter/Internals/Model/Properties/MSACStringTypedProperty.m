// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACStringTypedProperty.h"

@implementation MSACStringTypedProperty

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACStringTypedPropertyType;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _value = [coder decodeObjectForKey:kMSACTypedPropertyValue];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.value forKey:kMSACTypedPropertyValue];
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  dict[kMSACTypedPropertyValue] = self.value;
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACStringTypedProperty class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACStringTypedProperty *property = (MSACStringTypedProperty *)object;
  return ((!self.value && !property.value) || [self.value isEqualToString:property.value]);
}

@end
