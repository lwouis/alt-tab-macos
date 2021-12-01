// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#ifndef MSAC_EXCEPTION_MODEL_H
#define MSAC_EXCEPTION_MODEL_H

#if __has_include(<AppCenter/MSACSerializableObject.h>)
#import <AppCenter/MSACSerializableObject.h>
#else
#import "MSACSerializableObject.h"
#endif

@class MSACStackFrame;

NS_SWIFT_NAME(ExceptionModel)
@interface MSACExceptionModel : NSObject <MSACSerializableObject>

/**
 * Creates an instance of exception model.
 *
 * @param error error.
 *
 * @return A new instance of exception.
 */
- (instancetype)initWithError:(NSError *)error NS_SWIFT_NAME(init(withError:));

/**
 * Creates an instance of exception model.
 *
 * @param exceptionType exception type.
 * @param exceptionMessage exception message.
 * @param stackTrace stack trace.
 *
 * @return A new instance of exception.
 */
- (instancetype)initWithType:(NSString *)exceptionType
            exceptionMessage:(NSString *)exceptionMessage
                  stackTrace:(NSArray<NSString *> *)stackTrace
               NS_SWIFT_NAME(init(withType:exceptionMessage:stackTrace:));

/**
 * Creates an instance of exception model.
 *
 * @exception exception.
 *
 * @return A new instance of exception.
 */
- (instancetype)initWithException:(NSException *)exception NS_SWIFT_NAME(init(withException:));

/**
 * Exception type.
 */
@property(nonatomic, copy) NSString *type;

/**
 * Exception reason.
 */
@property(nonatomic, copy) NSString *message;

/**
 * Raw stack trace. Sent when the frames property is either missing or unreliable.
 */
@property(nonatomic, copy) NSString *stackTrace;

/**
 * Stack frames [optional].
 */
@property(nonatomic, strong) NSArray<MSACStackFrame *> *frames;

/**
 * Checks if the object's values are valid.
 *
 * @return YES, if the object is valid.
 */
- (BOOL)isValid;

@end

#endif
