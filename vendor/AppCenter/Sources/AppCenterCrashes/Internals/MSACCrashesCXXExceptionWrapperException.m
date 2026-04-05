// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCrashesCXXExceptionWrapperException.h"

@interface MSACCrashesCXXExceptionWrapperException ()

@property(readonly, nonatomic) const MSACCrashesUncaughtCXXExceptionInfo *info;

@end

@implementation MSACCrashesCXXExceptionWrapperException

- (instancetype)initWithCXXExceptionInfo:(const MSACCrashesUncaughtCXXExceptionInfo *)info {
  extern char *__cxa_demangle(const char *mangled_name, char *output_buffer, size_t *length, int *status);
  char *demangled_name = &__cxa_demangle ? __cxa_demangle(info->exception_type_name ?: "", NULL, NULL, NULL) : NULL;

  // stringWithUTF8String never returns null for us because we always send a correct string
  if ((self = [super initWithName:(NSString * _Nonnull)[NSString stringWithUTF8String:demangled_name ?: info->exception_type_name ?: ""]
                           reason:[NSString stringWithUTF8String:info->exception_message ?: ""]
                         userInfo:nil])) {
    _info = info;
  }
  return self;
}

/**
 * This method overrides [NSThread callStackReturnAddresses] and is crucial to report CXX exceptions. This is one of the "sneaky" things
 * that require knowledge of how PLCrashReporter works internally.
 */
- (NSArray *)callStackReturnAddresses {

  NSMutableArray *cxxFrames = [NSMutableArray arrayWithCapacity:self.info->exception_frames_count];

  for (uint32_t i = 0; i < self.info->exception_frames_count; ++i) {
    [cxxFrames addObject:@(self.info->exception_frames[i])];
  }

  return cxxFrames;
}

@end
