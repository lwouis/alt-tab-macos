// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCrashesUtil.h"
#import "MSACUtility+File.h"

@implementation MSACCrashesUtil

static dispatch_once_t crashesDirectoryOnceToken;
static dispatch_once_t logBufferDirectoryOnceToken;
static dispatch_once_t wrapperExceptionsDirectoryOnceToken;

#pragma mark - Public

+ (NSString *)crashesDir {
  dispatch_once(&crashesDirectoryOnceToken, ^{
    [MSACUtility createDirectoryForPathComponent:kMSACCrashesDirectory];
  });

  return kMSACCrashesDirectory;
}

+ (NSString *)logBufferDir {
  dispatch_once(&logBufferDirectoryOnceToken, ^{
    [MSACUtility createDirectoryForPathComponent:kMSACLogBufferDirectory];
  });

  return kMSACLogBufferDirectory;
}

+ (NSString *)wrapperExceptionsDir {
  dispatch_once(&wrapperExceptionsDirectoryOnceToken, ^{
    [MSACUtility createDirectoryForPathComponent:kMSACWrapperExceptionsDirectory];
  });

  return kMSACWrapperExceptionsDirectory;
}

#pragma mark - Private

+ (void)resetDirectory {
  crashesDirectoryOnceToken = 0;
  logBufferDirectoryOnceToken = 0;
  wrapperExceptionsDirectoryOnceToken = 0;
}

@end
