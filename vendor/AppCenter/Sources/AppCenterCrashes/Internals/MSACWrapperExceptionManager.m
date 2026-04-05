// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppCenterInternal.h"
#import "MSACCrashesInternal.h"
#import "MSACCrashesUtil.h"
#import "MSACWrapperExceptionModel.h"
#import "MSACLoggerInternal.h"
#import "MSACUtility+File.h"
#import "MSACWrapperExceptionInternal.h"
#import "MSACWrapperExceptionManagerInternal.h"

@implementation MSACWrapperExceptionManager : NSObject

static NSString *const kMSACLastWrapperExceptionFileName = @"last_saved_wrapper_exception";
static NSMutableDictionary *unprocessedWrapperExceptions;

+ (void)load {
  unprocessedWrapperExceptions = [NSMutableDictionary new];
}

#pragma mark Public Methods

/**
 * Gets a wrapper exception with a given UUID.
 */
+ (MSACWrapperException *)loadWrapperExceptionWithUUIDString:(NSString *)uuidString {
  MSACWrapperException *foundException = unprocessedWrapperExceptions[uuidString];
  return foundException ? foundException : [self loadWrapperExceptionWithBaseFilename:uuidString];
}

/**
 * Saves a wrapper exception to disk. Should only be used by wrapper SDK.
 */
+ (void)saveWrapperException:(MSACWrapperException *)wrapperException {
  [self saveWrapperException:wrapperException withBaseFilename:kMSACLastWrapperExceptionFileName];
}

#pragma mark Internal Methods

/**
 * Deletes a wrapper exception with a given UUID.
 */
+ (void)deleteWrapperExceptionWithUUIDString:(NSString *)uuidString {
  [self deleteWrapperExceptionWithBaseFilename:uuidString];
}

/**
 * Deletes all wrapper exceptions on disk.
 */
+ (void)deleteAllWrapperExceptions {
  [MSACUtility deleteItemForPathComponent:[MSACCrashesUtil wrapperExceptionsDir]];
}

/**
 * Renames the last saved wrapper exception with the error ID of the corresponding report in the given array. Pairing is based on the
 * process id of the error report.
 */
+ (void)correlateLastSavedWrapperExceptionToReport:(NSArray<MSACErrorReport *> *)reports {
  MSACWrapperException *lastSavedWrapperException = [self loadWrapperExceptionWithBaseFilename:kMSACLastWrapperExceptionFileName];

  // Delete the last saved exception from disk if it exists.
  if (lastSavedWrapperException) {
    [self deleteWrapperExceptionWithBaseFilename:kMSACLastWrapperExceptionFileName];
  }
  MSACErrorReport *correspondingReport = nil;
  for (MSACErrorReport *report in reports) {
    if ([lastSavedWrapperException.processId unsignedLongValue] == report.appProcessIdentifier) {
      correspondingReport = report;
      break;
    }
  }
  if (correspondingReport) {

    // As soon as the wrapper exception is correlated, store it in memory and save it to disk
    unprocessedWrapperExceptions[correspondingReport.incidentIdentifier] = lastSavedWrapperException;
    [self saveWrapperException:lastSavedWrapperException withBaseFilename:correspondingReport.incidentIdentifier];
  }
}

#pragma mark Helper methods

/**
 * Saves a wrapper exception to disk with the given file name.
 */
+ (void)saveWrapperException:(MSACWrapperException *)wrapperException withBaseFilename:(NSString *)baseFilename {

  // For some reason, archiving directly to a file fails in some cases, so archive to NSData and write that to the file
  NSData *data = [MSACUtility archiveKeyedData:wrapperException];
  NSString *pathComponent = [NSString stringWithFormat:@"%@/%@", [MSACCrashesUtil wrapperExceptionsDir], baseFilename];
  [MSACUtility createFileAtPathComponent:pathComponent withData:data atomically:YES forceOverwrite:YES];
}

/**
 * Deletes a wrapper exception with a given file name.
 */
+ (void)deleteWrapperExceptionWithBaseFilename:(NSString *)baseFilename {
  NSString *pathComponent = [NSString stringWithFormat:@"%@/%@", [MSACCrashesUtil wrapperExceptionsDir], baseFilename];
  [MSACUtility deleteItemForPathComponent:pathComponent];
}

/**
 * Loads a wrapper exception with a given filename.
 */
+ (MSACWrapperException *)loadWrapperExceptionWithBaseFilename:(NSString *)baseFilename {

  // For some reason, unarchiving directly from a file fails in some cases, so load data from a file and unarchive it after.
  NSString *pathComponent = [NSString stringWithFormat:@"%@/%@", [MSACCrashesUtil wrapperExceptionsDir], baseFilename];
  if (![MSACUtility fileExistsForPathComponent:pathComponent]) {
    return nil;
  }
  NSData *data = [MSACUtility loadDataForPathComponent:pathComponent];
  MSACWrapperException *wrapperException = nil;
  wrapperException = (MSACWrapperException *)[MSACUtility unarchiveKeyedData:data];
  if (!wrapperException) {
    MSACLogError([MSACCrashes logTag], @"Could not read exception data stored on disk with file name %@", baseFilename);
    [self deleteWrapperExceptionWithBaseFilename:baseFilename];
  }
  return wrapperException;
}

@end
