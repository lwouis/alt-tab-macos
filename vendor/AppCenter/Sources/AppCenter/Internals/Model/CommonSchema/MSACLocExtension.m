// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACLocExtension.h"

@implementation MSACLocExtension

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict;
  if (self.tz) {
    dict = [NSMutableDictionary new];
    dict[kMSACTimezone] = self.tz;
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
  if (![(NSObject *)object isKindOfClass:[MSACLocExtension class]]) {
    return NO;
  }

  MSACLocExtension *locExt = (MSACLocExtension *)object;
  return (!self.tz && !locExt.tz) || [self.tz isEqualToString:locExt.tz];
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super init])) {
    _tz = [coder decodeObjectForKey:kMSACTimezone];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.tz forKey:kMSACTimezone];
}

@end
