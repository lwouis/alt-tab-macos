// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "AppCenter+Internal.h"

@class MSACExceptionModel;
@class MSACStackFrame;

@interface MSACThread : NSObject <MSACSerializableObject>

/**
 * Thread identifier.
 */
@property(nonatomic) NSNumber *threadId;

/**
 * Thread name. [optional]
 */
@property(nonatomic, copy) NSString *name;

/**
 * Stack frames.
 */
@property(nonatomic) NSMutableArray<MSACStackFrame *> *frames;

/**
 * The last exception backtrace.
 */
@property(nonatomic) MSACExceptionModel *exception;

/**
 * Checks if the object's values are valid.
 *
 * @return YES, if the object is valid.
 */
- (BOOL)isValid;

@end
