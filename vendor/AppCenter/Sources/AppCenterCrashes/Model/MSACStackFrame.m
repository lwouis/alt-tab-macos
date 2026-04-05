// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACStackFrame.h"

static NSString *const kMSACAddress = @"address";
static NSString *const kMSACCode = @"code";
static NSString *const kMSACClassName = @"className";
static NSString *const kMSACMethodName = @"methodName";
static NSString *const kMSACLineNumber = @"lineNumber";
static NSString *const kMSACFileName = @"fileName";

@implementation MSACStackFrame

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [NSMutableDictionary new];

  if (self.address) {
    dict[kMSACAddress] = self.address;
  }
  if (self.code) {
    dict[kMSACCode] = self.code;
  }
  if (self.className) {
    dict[kMSACClassName] = self.className;
  }
  if (self.methodName) {
    dict[kMSACMethodName] = self.methodName;
  }
  if (self.lineNumber) {
    dict[kMSACLineNumber] = self.lineNumber;
  }
  if (self.fileName) {
    dict[kMSACFileName] = self.fileName;
  }
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACStackFrame class]]) {
    return NO;
  }
  MSACStackFrame *frame = (MSACStackFrame *)object;
  return ((!self.address && !frame.address) || [self.address isEqualToString:frame.address]) &&
         ((!self.code && !frame.code) || [self.code isEqualToString:frame.code]) &&
         ((!self.className && !frame.className) || [self.className isEqualToString:frame.className]) &&
         ((!self.methodName && !frame.methodName) || [self.methodName isEqualToString:frame.methodName]) &&
         ((!self.lineNumber && !frame.lineNumber) || [self.lineNumber isEqual:frame.lineNumber]) &&
         ((!self.fileName && !frame.fileName) || [self.fileName isEqualToString:frame.fileName]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  if (self) {
    _address = [coder decodeObjectForKey:kMSACAddress];
    _code = [coder decodeObjectForKey:kMSACCode];
    _className = [coder decodeObjectForKey:kMSACClassName];
    _methodName = [coder decodeObjectForKey:kMSACMethodName];
    _lineNumber = [coder decodeObjectForKey:kMSACLineNumber];
    _fileName = [coder decodeObjectForKey:kMSACFileName];
  }

  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:self.address forKey:kMSACAddress];
  [coder encodeObject:self.code forKey:kMSACCode];
  [coder encodeObject:self.className forKey:kMSACClassName];
  [coder encodeObject:self.methodName forKey:kMSACMethodName];
  [coder encodeObject:self.lineNumber forKey:kMSACLineNumber];
  [coder encodeObject:self.fileName forKey:kMSACFileName];
}

@end
