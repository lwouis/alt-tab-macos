// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACSessionHistoryInfo.h"

static NSString *const kMSACSessionIdKey = @"sessionIdKey";

/**
 * This class is used to associate session id with the timestamp that it was created.
 */
@implementation MSACSessionHistoryInfo

- (instancetype)initWithTimestamp:(NSDate *)timestamp andSessionId:(NSString *)sessionId {
  self = [super initWithTimestamp:timestamp];
  if (self) {
    _sessionId = sessionId;
  }
  return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _sessionId = [coder decodeObjectForKey:kMSACSessionIdKey];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.sessionId forKey:kMSACSessionIdKey];
}

@end
