// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACLogWithProperties.h"
#import "MSACAbstractLogInternal.h"

static NSString *const kMSACProperties = @"properties";

@implementation MSACLogWithProperties

@synthesize properties = _properties;

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];

  if (self.properties && [self.properties count] != 0) {
    dict[kMSACProperties] = self.properties;
  }
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACLogWithProperties class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACLogWithProperties *log = (MSACLogWithProperties *)object;
  return ((!self.properties && !log.properties) || [self.properties isEqualToDictionary:log.properties]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _properties = [coder decodeObjectForKey:kMSACProperties];
  }

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.properties forKey:kMSACProperties];
}

@end
