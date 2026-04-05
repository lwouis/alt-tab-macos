// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCSData.h"
#import "MSACOrderedDictionary.h"

@implementation MSACCSData

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict;
  if (self.properties) {
    dict = [MSACOrderedDictionary new];

    // ORDER MATTERS: Make sure baseType and baseData appear first in part B
    if (self.properties[kMSACDataBaseType]) {
      dict[kMSACDataBaseType] = self.properties[kMSACDataBaseType];
    }
    if (self.properties[kMSACDataBaseData]) {
      dict[kMSACDataBaseData] = self.properties[kMSACDataBaseData];
    }
    [dict addEntriesFromDictionary:self.properties];
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
  if (![(NSObject *)object isKindOfClass:[MSACCSData class]]) {
    return NO;
  }
  MSACCSData *csData = (MSACCSData *)object;
  return (!self.properties && !csData.properties) || [self.properties isEqualToDictionary:csData.properties];
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _properties = [coder decodeObject];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeRootObject:self.properties];
}

@end
