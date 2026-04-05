// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACStartServiceLog.h"

static NSString *const kMSACStartService = @"startService";
static NSString *const kMSACServices = @"services";

@implementation MSACStartServiceLog

@synthesize services = _services;

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACStartService;
  }
  return self;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACStartServiceLog class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACStartServiceLog *log = (MSACStartServiceLog *)object;
  return ((!self.services && !log.services) || [self.services isEqualToArray:log.services]);
}

#pragma mark - MSACSerializableObject

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  if (self.services) {
    dict[kMSACServices] = self.services;
  }
  return dict;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  if ((self = [super initWithCoder:coder])) {
    self.services = [coder decodeObjectForKey:kMSACServices];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.services forKey:kMSACServices];
}

@end
