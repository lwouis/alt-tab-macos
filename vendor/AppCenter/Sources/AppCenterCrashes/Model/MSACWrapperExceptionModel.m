// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACWrapperExceptionModel.h"
#import "MSACExceptionModel.h"
#import "MSACStackFrame.h"

static NSString *const kMSACInnerExceptions = @"innerExceptions";
static NSString *const kMSACWrapperSDKName = @"wrapperSdkName";

@implementation MSACWrapperExceptionModel

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];
  if (self.wrapperSdkName) {
    dict[kMSACWrapperSDKName] = self.wrapperSdkName;
  }
  if (self.innerExceptions) {
    NSMutableArray *exceptionsArray = [NSMutableArray array];
    for (MSACWrapperExceptionModel *exception in self.innerExceptions) {
      [exceptionsArray addObject:[exception serializeToDictionary]];
    }
    dict[kMSACInnerExceptions] = exceptionsArray;
  }
  return dict;
}

- (BOOL)isValid {
  return [super isValid];
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACWrapperExceptionModel class]]) {
    return NO;
  }
  MSACWrapperExceptionModel *exception = (MSACWrapperExceptionModel *)object;
  return [super isEqual:object] &&
         ((!self.wrapperSdkName && !exception.wrapperSdkName) || [self.wrapperSdkName isEqualToString:exception.wrapperSdkName]) &&
         ((!self.innerExceptions && !exception.innerExceptions) || [self.innerExceptions isEqualToArray:exception.innerExceptions]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _innerExceptions = [coder decodeObjectForKey:kMSACInnerExceptions];
    _wrapperSdkName = [coder decodeObjectForKey:kMSACWrapperSDKName];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.innerExceptions forKey:kMSACInnerExceptions];
  [coder encodeObject:self.wrapperSdkName forKey:kMSACWrapperSDKName];
}

@end
