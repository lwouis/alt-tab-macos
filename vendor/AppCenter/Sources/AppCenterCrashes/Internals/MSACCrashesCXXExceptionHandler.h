// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

/**
 * Struct to describe CXXException information.
 */
typedef struct {
  const void *__nullable exception;
  const char *__nullable exception_type_name;
  const char *__nullable exception_message;
  uint32_t exception_frames_count;
  const uintptr_t *__nonnull exception_frames;
} MSACCrashesUncaughtCXXExceptionInfo;

typedef void (*MSACCrashesUncaughtCXXExceptionHandler)(const MSACCrashesUncaughtCXXExceptionInfo *__nonnull info);

@interface MSACCrashesUncaughtCXXExceptionHandlerManager : NSObject

/**
 * Add a XCXX exceptionHandler.
 *
 * @param handler The MSACCrashesUncaughtCXXExceptionHandler that should be added.
 */
+ (void)addCXXExceptionHandler:(nonnull MSACCrashesUncaughtCXXExceptionHandler)handler;

/**
 * Remove a XCXX exceptionHandler.
 *
 * @param handler The MSACCrashesUncaughtCXXExceptionHandler that should be removed.
 */
+ (void)removeCXXExceptionHandler:(nonnull MSACCrashesUncaughtCXXExceptionHandler)handler;

/**
 * Handlers count
 */
+ (NSUInteger)countCXXExceptionHandler;

@end
