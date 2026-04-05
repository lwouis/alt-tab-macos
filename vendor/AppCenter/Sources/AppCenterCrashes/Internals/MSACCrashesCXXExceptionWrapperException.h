// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACCrashesCXXExceptionHandler.h"

/**
 * Temporary class until PLCR catches up. We trick PLCR with an Objective-C exception. This code provides us access to the C++ exception
 * message, including a correct stack trace.
 */
@interface MSACCrashesCXXExceptionWrapperException : NSException

- (instancetype)initWithCXXExceptionInfo:(const MSACCrashesUncaughtCXXExceptionInfo *)info;

@end
