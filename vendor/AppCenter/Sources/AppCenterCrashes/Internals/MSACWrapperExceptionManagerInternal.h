// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACWrapperExceptionManager.h"

@class MSACErrorReport;
@class MSACWrapperException;

@interface MSACWrapperExceptionManager ()

/**
 * Delete all wrapper exception files on disk.
 */
+ (void)deleteAllWrapperExceptions;

/**
 * Find the PLCrashReport with a matching process id to the MSACWrapperException that was last saved on disk, and update the filename to the
 * report's UUID.
 */
+ (void)correlateLastSavedWrapperExceptionToReport:(NSArray<MSACErrorReport *> *)reports;

/**
 * Delete a wrapper exception with a given UUID.
 */
+ (void)deleteWrapperExceptionWithUUIDString:(NSString *)uuidString;

@end
