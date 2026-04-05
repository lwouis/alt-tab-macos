// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHistoryInfo.h"

static NSString *const kMSACTimestampKey = @"timestampKey";

/**
 * This class is a base class for maintaining history of data in time order.
 */
@implementation MSACHistoryInfo

- (instancetype)initWithTimestamp:(NSDate *)timestamp {
  self = [super init];
  if (self) {
    _timestamp = timestamp;
  }
  return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _timestamp = [coder decodeObjectForKey:kMSACTimestampKey];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.timestamp forKey:kMSACTimestampKey];
}

@end
