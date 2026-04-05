// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACThread.h"
#import "MSACExceptionModel.h"
#import "MSACStackFrame.h"

static NSString *const kMSACThreadId = @"id";
static NSString *const kMSACName = @"name";
static NSString *const kMSACStackFrames = @"frames";
static NSString *const kMSACException = @"exception";

@implementation MSACThread

// Initializes a new instance of the class.
- (instancetype)init {
  if ((self = [super init])) {
    _frames = [NSMutableArray array];
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];

  if (self.threadId) {
    dict[kMSACThreadId] = self.threadId;
  }
  if (self.name) {
    dict[kMSACName] = self.name;
  }

  if (self.frames) {
    NSMutableArray *framesArray = [NSMutableArray array];
    for (MSACStackFrame *frame in self.frames) {
      [framesArray addObject:[frame serializeToDictionary]];
    }
    dict[kMSACStackFrames] = framesArray;
  }

  if (self.exception) {
    dict[kMSACException] = [self.exception serializeToDictionary];
  }

  return dict;
}

- (BOOL)isValid {
  return MSACLOG_VALIDATE_NOT_NIL(threadId) && MSACLOG_VALIDATE(frames, [self.frames count] > 0);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACThread class]]) {
    return NO;
  }
  MSACThread *thread = (MSACThread *)object;
  return ((!self.threadId && !thread.threadId) || [self.threadId isEqual:thread.threadId]) &&
         ((!self.name && !thread.name) || [self.name isEqualToString:thread.name]) &&
         ((!self.frames && !thread.frames) || [self.frames isEqualToArray:thread.frames]) &&
         ((!self.exception && !thread.exception) || [self.exception isEqual:thread.exception]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _threadId = [coder decodeObjectForKey:kMSACThreadId];
    _name = [coder decodeObjectForKey:kMSACName];
    _frames = [coder decodeObjectForKey:kMSACStackFrames];
    _exception = [coder decodeObjectForKey:kMSACException];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.threadId forKey:kMSACThreadId];
  [coder encodeObject:self.name forKey:kMSACName];
  [coder encodeObject:self.frames forKey:kMSACStackFrames];
  [coder encodeObject:self.exception forKey:kMSACException];
}

@end
