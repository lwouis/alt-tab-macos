// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAbstractErrorLog.h"

static NSString *const kMSACId = @"id";
static NSString *const kMSACProcessId = @"processId";
static NSString *const kMSACProcessName = @"processName";
static NSString *const kMSACParentProcessId = @"parentProcessId";
static NSString *const kMSACParentProcessName = @"parentProcessName";
static NSString *const kMSACErrorThreadId = @"errorThreadId";
static NSString *const kMSACErrorThreadName = @"errorThreadName";
static NSString *const kMSACFatal = @"fatal";
static NSString *const kMSACAppLaunchTimestamp = @"appLaunchTimestamp";
static NSString *const kMSACArchitecture = @"architecture";

@implementation MSACAbstractErrorLog

@synthesize errorId = _id;
@synthesize processId = _processId;
@synthesize processName = _processName;
@synthesize parentProcessId = _parentProcessId;
@synthesize parentProcessName = _parentProcessName;
@synthesize errorThreadId = _errorThreadId;
@synthesize errorThreadName = _errorThreadName;
@synthesize fatal = _fatal;
@synthesize appLaunchTimestamp = _appLaunchTimestamp;
@synthesize architecture = _architecture;

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];

  if (self.errorId) {
    dict[kMSACId] = self.errorId;
  }
  if (self.processId) {
    dict[kMSACProcessId] = self.processId;
  }
  if (self.processName) {
    dict[kMSACProcessName] = self.processName;
  }
  if (self.parentProcessId) {
    dict[kMSACParentProcessId] = self.parentProcessId;
  }
  if (self.parentProcessName) {
    dict[kMSACParentProcessName] = self.parentProcessName;
  }
  if (self.errorThreadId) {
    dict[kMSACErrorThreadId] = self.errorThreadId;
  }
  if (self.errorThreadName) {
    dict[kMSACErrorThreadName] = self.errorThreadName;
  }
  dict[kMSACFatal] = self.fatal ? @YES : @NO;
  if (self.appLaunchTimestamp) {
    dict[kMSACAppLaunchTimestamp] = [MSACUtility dateToISO8601:self.appLaunchTimestamp];
  }
  if (self.architecture) {
    dict[kMSACArchitecture] = self.architecture;
  }

  return dict;
}

- (BOOL)isValid {
  return
      [super isValid] && MSACLOG_VALIDATE_NOT_NIL(errorId) && MSACLOG_VALIDATE_NOT_NIL(processId) && MSACLOG_VALIDATE_NOT_NIL(processName);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACAbstractErrorLog class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACAbstractErrorLog *errorLog = (MSACAbstractErrorLog *)object;
  return ((!self.errorId && !errorLog.errorId) || [self.errorId isEqualToString:errorLog.errorId]) &&
         ((!self.processId && !errorLog.processId) || [self.processId isEqual:errorLog.processId]) &&
         ((!self.processName && !errorLog.processName) || [self.processName isEqualToString:errorLog.processName]) &&
         ((!self.parentProcessId && !errorLog.parentProcessId) || [self.parentProcessId isEqual:errorLog.parentProcessId]) &&
         ((!self.parentProcessName && !errorLog.parentProcessName) ||
          [self.parentProcessName isEqualToString:errorLog.parentProcessName]) &&
         ((!self.errorThreadId && !errorLog.errorThreadId) || [self.errorThreadId isEqual:errorLog.errorThreadId]) &&
         ((!self.errorThreadName && !errorLog.errorThreadName) || [self.errorThreadName isEqualToString:errorLog.errorThreadName]) &&
         (self.fatal == errorLog.fatal) &&
         ((!self.appLaunchTimestamp && !errorLog.appLaunchTimestamp) || [self.appLaunchTimestamp isEqual:errorLog.appLaunchTimestamp]) &&
         ((!self.architecture && !errorLog.architecture) || [self.architecture isEqualToString:errorLog.architecture]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _id = [coder decodeObjectForKey:kMSACId];
    _processId = [coder decodeObjectForKey:kMSACProcessId];
    _processName = [coder decodeObjectForKey:kMSACProcessName];
    _parentProcessId = [coder decodeObjectForKey:kMSACParentProcessId];
    _parentProcessName = [coder decodeObjectForKey:kMSACParentProcessName];
    _errorThreadId = [coder decodeObjectForKey:kMSACErrorThreadId];
    _errorThreadName = [coder decodeObjectForKey:kMSACErrorThreadName];
    _fatal = [coder decodeBoolForKey:kMSACFatal];
    _appLaunchTimestamp = [coder decodeObjectForKey:kMSACAppLaunchTimestamp];
    _architecture = [coder decodeObjectForKey:kMSACArchitecture];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.errorId forKey:kMSACId];
  [coder encodeObject:self.processId forKey:kMSACProcessId];
  [coder encodeObject:self.processName forKey:kMSACProcessName];
  [coder encodeObject:self.parentProcessId forKey:kMSACParentProcessId];
  [coder encodeObject:self.parentProcessName forKey:kMSACParentProcessName];
  [coder encodeObject:self.errorThreadId forKey:kMSACErrorThreadId];
  [coder encodeObject:self.errorThreadName forKey:kMSACErrorThreadName];
  [coder encodeBool:self.fatal forKey:kMSACFatal];
  [coder encodeObject:self.appLaunchTimestamp forKey:kMSACAppLaunchTimestamp];
  [coder encodeObject:self.architecture forKey:kMSACArchitecture];
}

@end
