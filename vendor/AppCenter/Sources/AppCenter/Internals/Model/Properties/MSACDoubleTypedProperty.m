// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDoubleTypedProperty.h"

@implementation MSACDoubleTypedProperty

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACDoubleTypedPropertyType;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _value = [coder decodeDoubleForKey:kMSACTypedPropertyValue];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeDouble:self.value forKey:kMSACTypedPropertyValue];
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  dict[kMSACTypedPropertyValue] = @(self.value);
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACDoubleTypedProperty class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACDoubleTypedProperty *property = (MSACDoubleTypedProperty *)object;
  return (self.value == property.value);
}

@end
