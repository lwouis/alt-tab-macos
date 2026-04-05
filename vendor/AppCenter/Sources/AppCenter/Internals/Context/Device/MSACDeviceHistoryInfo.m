// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACDeviceHistoryInfo.h"

static NSString *const kMSACDeviceKey = @"deviceKey";

/**
 * This class is used to associate device properties with the timestamp that it was created with.
 */
@implementation MSACDeviceHistoryInfo

- (instancetype)initWithTimestamp:(NSDate *)timestamp andDevice:(MSACDevice *)device {
  self = [super initWithTimestamp:timestamp];
  if (self) {
    _device = device;
  }
  return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    self.device = [coder decodeObjectForKey:kMSACDeviceKey];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.device forKey:kMSACDeviceKey];
}

@end
