// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACBooleanTypedProperty.h"

@implementation MSACBooleanTypedProperty

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACBooleanTypedPropertyType;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _value = [coder decodeBoolForKey:kMSACTypedPropertyValue];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeBool:self.value forKey:kMSACTypedPropertyValue];
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  dict[kMSACTypedPropertyValue] = @(self.value);
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACBooleanTypedProperty class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACBooleanTypedProperty *property = (MSACBooleanTypedProperty *)object;
  return (self.value == property.value);
}

@end
