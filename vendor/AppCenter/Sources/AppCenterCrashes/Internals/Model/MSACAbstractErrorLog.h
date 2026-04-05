// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "AppCenter+Internal.h"
#if __has_include(<AppCenter/MSACLogWithProperties.h>)
#import <AppCenter/MSACLogWithProperties.h>
#else
#import "MSACLogWithProperties.h"
#endif

@class MSACErrorAttachment;

@interface MSACAbstractErrorLog : MSACLogWithProperties

/**
 * Error identifier.
 */
@property(nonatomic, copy) NSString *errorId;

/**
 * Process identifier.
 */
@property(nonatomic) NSNumber *processId;

/**
 * Process name.
 */
@property(nonatomic, copy) NSString *processName;

/**
 * Parent's process identifier. [optional]
 */
@property(nonatomic) NSNumber *parentProcessId;

/**
 * Name of the parent's process. [optional]
 */
@property(nonatomic, copy) NSString *parentProcessName;

/**
 * Error thread identifier. [optional]
 */
@property(nonatomic) NSNumber *errorThreadId;

/**
 * Error thread name. [optional]
 */
@property(nonatomic, copy) NSString *errorThreadName;

/**
 * If YES, this error report is an application crash.
 */
@property(nonatomic, getter=isFatal) BOOL fatal;

/**
 * Timestamp when the app was launched.
 */
@property(nonatomic) NSDate *appLaunchTimestamp;

/**
 * CPU Architecture. [optional]
 */
@property(nonatomic, copy) NSString *architecture;

@end
