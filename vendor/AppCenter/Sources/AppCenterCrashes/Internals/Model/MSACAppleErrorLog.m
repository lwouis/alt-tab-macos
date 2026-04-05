// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppleErrorLog.h"
#import "MSACBinary.h"
#import "MSACExceptionModel.h"
#import "MSACThread.h"

static NSString *const kMSACTypeError = @"appleError";
static NSString *const kMSACPrimaryArchitectureId = @"primaryArchitectureId";
static NSString *const kMSACArchitectureVariantId = @"architectureVariantId";
static NSString *const kMSACApplicationPath = @"applicationPath";
static NSString *const kMSACOsExceptionType = @"osExceptionType";
static NSString *const kMSACOsExceptionCode = @"osExceptionCode";
static NSString *const kMSACOsExceptionAddress = @"osExceptionAddress";
static NSString *const kMSACExceptionType = @"exceptionType";
static NSString *const kMSACExceptionReason = @"exceptionReason";
static NSString *const kMSACSelectorRegisterValue = @"selectorRegisterValue";
static NSString *const kMSACThreads = @"threads";
static NSString *const kMSACBinaries = @"binaries";
static NSString *const kMSACRegisters = @"registers";
static NSString *const kMSACException = @"exception";

@implementation MSACAppleErrorLog

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACTypeError;
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];

  if (self.primaryArchitectureId) {
    dict[kMSACPrimaryArchitectureId] = self.primaryArchitectureId;
  }
  if (self.architectureVariantId) {
    dict[kMSACArchitectureVariantId] = self.architectureVariantId;
  }
  if (self.applicationPath) {
    dict[kMSACApplicationPath] = self.applicationPath;
  }
  if (self.osExceptionType) {
    dict[kMSACOsExceptionType] = self.osExceptionType;
  }
  if (self.osExceptionCode) {
    dict[kMSACOsExceptionCode] = self.osExceptionCode;
  }
  if (self.osExceptionAddress) {
    dict[kMSACOsExceptionAddress] = self.osExceptionAddress;
  }
  if (self.exceptionType) {
    dict[kMSACExceptionType] = self.exceptionType;
  }
  if (self.exceptionReason) {
    dict[kMSACExceptionReason] = self.exceptionReason;
  }
  if (self.selectorRegisterValue) {
    dict[kMSACSelectorRegisterValue] = self.selectorRegisterValue;
  }
  if (self.threads) {
    NSMutableArray *threadsArray = [NSMutableArray array];
    for (MSACThread *thread in self.threads) {
      [threadsArray addObject:[thread serializeToDictionary]];
    }
    dict[kMSACThreads] = threadsArray;
  }
  if (self.binaries) {
    NSMutableArray *binariesArray = [NSMutableArray array];
    for (MSACBinary *binary in self.binaries) {
      [binariesArray addObject:[binary serializeToDictionary]];
    }
    dict[kMSACBinaries] = binariesArray;
  }
  if (self.registers) {
    dict[kMSACRegisters] = self.registers;
  }
  if (self.exception) {
    dict[kMSACException] = [self.exception serializeToDictionary];
  }

  return dict;
}

- (BOOL)isValid {
  return [super isValid] && MSACLOG_VALIDATE_NOT_NIL(primaryArchitectureId) && MSACLOG_VALIDATE_NOT_NIL(applicationPath) &&
         MSACLOG_VALIDATE_NOT_NIL(osExceptionType) && MSACLOG_VALIDATE_NOT_NIL(osExceptionCode) &&
         MSACLOG_VALIDATE_NOT_NIL(osExceptionAddress);
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACAppleErrorLog class]] || ![super isEqual:object]) {
    return NO;
  }
  MSACAppleErrorLog *errorLog = (MSACAppleErrorLog *)object;
  return ((!self.primaryArchitectureId && !errorLog.primaryArchitectureId) ||
          [self.primaryArchitectureId isEqual:errorLog.primaryArchitectureId]) &&
         ((!self.architectureVariantId && !errorLog.architectureVariantId) ||
          [self.architectureVariantId isEqual:errorLog.architectureVariantId]) &&
         ((!self.applicationPath && !errorLog.applicationPath) || [self.applicationPath isEqualToString:errorLog.applicationPath]) &&
         ((!self.osExceptionType && !errorLog.osExceptionType) || [self.osExceptionType isEqualToString:errorLog.osExceptionType]) &&
         ((!self.osExceptionCode && !errorLog.osExceptionCode) || [self.osExceptionCode isEqualToString:errorLog.osExceptionCode]) &&
         ((!self.osExceptionAddress && !errorLog.osExceptionAddress) ||
          [self.osExceptionAddress isEqualToString:errorLog.osExceptionAddress]) &&
         ((!self.exceptionType && !errorLog.exceptionType) || [self.exceptionType isEqualToString:errorLog.exceptionType]) &&
         ((!self.exceptionReason && !errorLog.exceptionReason) || [self.exceptionReason isEqualToString:errorLog.exceptionReason]) &&
         ((!self.selectorRegisterValue && !errorLog.selectorRegisterValue) ||
          ([self.selectorRegisterValue isEqualToString:errorLog.selectorRegisterValue])) &&
         ((!self.threads && !errorLog.threads) || [self.threads isEqualToArray:errorLog.threads]) &&
         ((!self.binaries && !errorLog.binaries) || [self.binaries isEqualToArray:errorLog.binaries]) &&
         ((!self.registers && !errorLog.registers) || [self.registers isEqualToDictionary:errorLog.registers]) &&
         ((!self.exception && !errorLog.exception) || [self.exception isEqual:errorLog.exception]);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _primaryArchitectureId = [coder decodeObjectForKey:kMSACPrimaryArchitectureId];
    _architectureVariantId = [coder decodeObjectForKey:kMSACArchitectureVariantId];
    _applicationPath = [coder decodeObjectForKey:kMSACApplicationPath];
    _osExceptionType = [coder decodeObjectForKey:kMSACOsExceptionType];
    _osExceptionCode = [coder decodeObjectForKey:kMSACOsExceptionCode];
    _osExceptionAddress = [coder decodeObjectForKey:kMSACOsExceptionAddress];
    _exceptionType = [coder decodeObjectForKey:kMSACExceptionType];
    _exceptionReason = [coder decodeObjectForKey:kMSACExceptionReason];
    _selectorRegisterValue = [coder decodeObjectForKey:kMSACSelectorRegisterValue];
    _threads = [coder decodeObjectForKey:kMSACThreads];
    _binaries = [coder decodeObjectForKey:kMSACBinaries];
    _registers = [coder decodeObjectForKey:kMSACRegisters];
    _exception = [coder decodeObjectForKey:kMSACException];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.primaryArchitectureId forKey:kMSACPrimaryArchitectureId];
  [coder encodeObject:self.architectureVariantId forKey:kMSACArchitectureVariantId];
  [coder encodeObject:self.applicationPath forKey:kMSACApplicationPath];
  [coder encodeObject:self.osExceptionType forKey:kMSACOsExceptionType];
  [coder encodeObject:self.osExceptionCode forKey:kMSACOsExceptionCode];
  [coder encodeObject:self.osExceptionAddress forKey:kMSACOsExceptionAddress];
  [coder encodeObject:self.exceptionType forKey:kMSACExceptionType];
  [coder encodeObject:self.exceptionReason forKey:kMSACExceptionReason];
  [coder encodeObject:self.selectorRegisterValue forKey:kMSACSelectorRegisterValue];
  [coder encodeObject:self.threads forKey:kMSACThreads];
  [coder encodeObject:self.binaries forKey:kMSACBinaries];
  [coder encodeObject:self.registers forKey:kMSACRegisters];
  [coder encodeObject:self.exception forKey:kMSACException];
}

@end
