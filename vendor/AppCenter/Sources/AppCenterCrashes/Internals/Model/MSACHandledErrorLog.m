// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHandledErrorLog.h"
#import "MSACExceptionModel.h"

static NSString *const kMSACTypeError = @"handledError";
static NSString *const kMSACId = @"id";
static NSString *const kMSACException = @"exception";

@implementation MSACHandledErrorLog

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACTypeError;
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];

  if (self.errorId) {
    dict[kMSACId] = self.errorId;
  }
  if (self.exception) {
    dict[kMSACException] = [self.exception serializeToDictionary];
  }
  return dict;
}

- (BOOL)isValid {
  return [super isValid] && MSACLOG_VALIDATE_NOT_NIL(errorId) && MSACLOG_VALIDATE_NOT_NIL(exception);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACHandledErrorLog class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACHandledErrorLog *errorLog = (MSACHandledErrorLog *)object;
  return ((!self.errorId && !errorLog.errorId) || [self.errorId isEqual:errorLog.errorId]) &&
         ((!self.exception && !errorLog.exception) || [self.exception isEqual:errorLog.exception]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _errorId = [coder decodeObjectForKey:kMSACId];
    _exception = [coder decodeObjectForKey:kMSACException];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.errorId forKey:kMSACId];
  [coder encodeObject:self.exception forKey:kMSACException];
}

@end
