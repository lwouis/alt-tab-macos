// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACWrapperExceptionModel.h"
#import "MSACWrapperExceptionInternal.h"

@implementation MSACWrapperException

static NSString *const kMSACModelException = @"modelException";
static NSString *const kMSACExceptionData = @"exceptionData";
static NSString *const KMSACProcessId = @"processId";

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.modelException) {
    dict[kMSACModelException] = [self.modelException serializeToDictionary];
  }
  if (self.processId) {
    dict[KMSACProcessId] = self.processId;
  }
  if (self.exceptionData) {
    dict[kMSACExceptionData] = self.exceptionData;
  }
  return dict;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    self.modelException = [coder decodeObjectForKey:kMSACModelException];
    self.exceptionData = [coder decodeObjectForKey:kMSACExceptionData];
    self.processId = [coder decodeObjectForKey:KMSACProcessId];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.modelException forKey:kMSACModelException];
  [coder encodeObject:self.exceptionData forKey:kMSACExceptionData];
  [coder encodeObject:self.processId forKey:KMSACProcessId];
}

@end
