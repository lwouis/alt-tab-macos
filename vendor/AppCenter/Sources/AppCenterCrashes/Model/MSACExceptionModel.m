// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "AppCenter+Internal.h"
#import "MSACExceptionModel.h"
#import "MSACStackFrame.h"

static NSString *const kMSACExceptionFrames = @"frames";
static NSString *const kMSACExceptionType = @"type";
static NSString *const kMSACExceptionMessage = @"message";
static NSString *const kMSACExceptionStackTrace = @"stackTrace";

@implementation MSACExceptionModel

- (instancetype)initWithError:(NSError *)error {
  self = [super init];
  if (self) {
    if (error.domain) {
      self.type = error.domain;
    }
    if (error.userInfo && error.userInfo.count > 0) {
      self.message = error.userInfo.description;
    }
    NSArray<NSString *> *stackTraceArray = [NSThread callStackSymbols];
    self.stackTrace = stackTraceArray.description;
    self.frames = [MSACExceptionModel loadStackTrace:stackTraceArray];
  }
  return self;
}

- (instancetype)initWithException:(NSException *)exception {
  self = [super init];
  if (self) {
    if ([exception respondsToSelector:NSSelectorFromString(@"name")]) {
      self.type = exception.name;
    }
    if ([exception respondsToSelector:NSSelectorFromString(@"reason")]) {
      self.message = exception.reason;
    }
    NSArray<MSACStackFrame *> *frames;
    if ([exception respondsToSelector:NSSelectorFromString(@"callStackSymbols")]) {
      self.stackTrace = exception.callStackSymbols.description;
      frames = [MSACExceptionModel loadStackTrace:exception.callStackSymbols];
    } else {
      frames = [MSACExceptionModel loadStackTrace:[NSThread callStackSymbols]];
    }
    self.frames = frames;
  }
  return self;
}

- (instancetype)initWithType:(NSString *)exceptionType
            exceptionMessage:(NSString *)exceptionMessage
                  stackTrace:(NSArray<NSString *> *)stackTrace {
  self = [super init];
  if (self) {
    self.type = exceptionType;
    self.message = exceptionMessage;
    if (stackTrace == nil) {
      stackTrace = [NSThread callStackSymbols];
    }
    self.stackTrace = stackTrace.description;
    self.frames = [MSACExceptionModel loadStackTrace:stackTrace];
  }
  return self;
}

+ (NSArray<MSACStackFrame *> *)loadStackTrace:(NSArray<NSString *> *)stackTrace {
  NSMutableArray<MSACStackFrame *> *frames = [NSMutableArray<MSACStackFrame *> new];
  for (NSString *line in stackTrace) {
    NSCharacterSet *separatorSet = [NSCharacterSet characterSetWithCharactersInString:@" -[]+?.,"];
    NSMutableArray *array = [NSMutableArray arrayWithArray:[line componentsSeparatedByCharactersInSet:separatorSet]];
    [array removeObject:@""];
    MSACStackFrame *frame = [MSACStackFrame new];

    // If the stack trace line doesn't contain full information it should be ignored.
    if (array.count > 5) {
      frame.fileName = [array objectAtIndex:1];
      frame.address = [array objectAtIndex:2];
      frame.className = [array objectAtIndex:3];
      frame.methodName = [array objectAtIndex:4];
      [frames addObject:frame];
    }
  }
  return frames;
}

- (BOOL)isValid {
  return MSACLOG_VALIDATE_NOT_NIL(type) && MSACLOG_VALIDATE(frames, [self.frames count] > 0);
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];
  if (self.type) {
    dict[kMSACExceptionType] = self.type;
  }
  if (self.message) {
    dict[kMSACExceptionMessage] = self.message;
  }
  if (self.stackTrace) {
    dict[kMSACExceptionStackTrace] = self.stackTrace;
  }
  if (self.frames) {
    NSMutableArray *framesArray = [NSMutableArray array];
    for (MSACStackFrame *frame in self.frames) {
      [framesArray addObject:[frame serializeToDictionary]];
    }
    dict[kMSACExceptionFrames] = framesArray;
  }
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACExceptionModel class]]) {
    return NO;
  }
  MSACExceptionModel *exception = (MSACExceptionModel *)object;
  return ((!self.type && !exception.type) || [self.type isEqualToString:exception.type]) &&
         ((!self.message && !exception.message) || [self.message isEqualToString:exception.message]) &&
         ((!self.frames && !exception.frames) || [self.frames isEqualToArray:exception.frames]) &&
         ((!self.stackTrace && !exception.stackTrace) || [self.stackTrace isEqualToString:exception.stackTrace]);
}

#pragma mark - NSCoding

- (nullable instancetype)initWithCoder:(nonnull NSCoder *)coder {
  self = [super init];
  if (self) {
    self.type = [coder decodeObjectForKey:kMSACExceptionType];
    self.message = [coder decodeObjectForKey:kMSACExceptionMessage];
    self.stackTrace = [coder decodeObjectForKey:kMSACExceptionStackTrace];
    self.frames = [coder decodeObjectForKey:kMSACExceptionFrames];
  }
  return self;
}

- (void)encodeWithCoder:(nonnull NSCoder *)coder {
  [coder encodeObject:self.type forKey:kMSACExceptionType];
  [coder encodeObject:self.message forKey:kMSACExceptionMessage];
  [coder encodeObject:self.stackTrace forKey:kMSACExceptionStackTrace];
  [coder encodeObject:self.frames forKey:kMSACExceptionFrames];
}

@end
