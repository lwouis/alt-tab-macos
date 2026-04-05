// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACUserIdHistoryInfo.h"

static NSString *const kMSACUserIdKey = @"userIdKey";

/**
 * This class is used to associate user id with the timestamp that it was created.
 */
@implementation MSACUserIdHistoryInfo

- (instancetype)initWithTimestamp:(NSDate *)timestamp andUserId:(NSString *)userId {
  self = [super initWithTimestamp:timestamp];
  if (self) {
    _userId = userId;
  }
  return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _userId = [coder decodeObjectForKey:kMSACUserIdKey];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.userId forKey:kMSACUserIdKey];
}

@end
