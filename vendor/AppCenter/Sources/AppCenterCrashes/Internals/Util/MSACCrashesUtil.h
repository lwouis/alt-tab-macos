// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

static NSString *const kMSACCrashesDirectory = @"crashes";
static NSString *const kMSACLogBufferDirectory = @"crasheslogbuffer";
static NSString *const kMSACWrapperExceptionsDirectory = @"crasheswrapperexceptions";

@interface MSACCrashesUtil : NSObject

/**
 * Returns the directory for storing and reading crash reports for this app.
 *
 * @return The directory containing crash reports for this app.
 */
+ (NSString *)crashesDir;

/**
 * Returns the directory for storing and reading buffered logs. It will be used in case we crash to make sure we don't lose any data.
 *
 * @return The directory containing buffered events for an app
 */
+ (NSString *)logBufferDir;

/**
 * Returns the directory for storing and reading wrapper exception data.
 *
 * @return The directory containing wrapper exception data.
 */
+ (NSString *)wrapperExceptionsDir;

@end
