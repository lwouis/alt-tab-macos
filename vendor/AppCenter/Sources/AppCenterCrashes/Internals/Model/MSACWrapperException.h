// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@class MSACExceptionModel;

/**
 * This class represents a wrapper exception that augments the data recorded when the application crashes.
 */
@interface MSACWrapperException : NSObject

/**
 * The model exception for the corresponding crash.
 */
@property(nonatomic) MSACExceptionModel *modelException;

/**
 * Additional data that the wrapper SDK needs to save.
 */
@property(nonatomic) NSData *exceptionData;

/**
 * Id of the crashed process; used for correlation to a PLCrashReport.
 */
@property(nonatomic, copy) NSNumber *processId;

@end
