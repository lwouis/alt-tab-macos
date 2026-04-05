// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACChannelDelegate.h"
#import "MSACCrashes.h"

@class PLCrashReporter;

@interface MSACCrashes () <MSACChannelDelegate>

/**
 * Prototype of a callback function used to execute additional user code. Called
 * upon completion of crash handling, after the crash report has been written to
 * disk.
 *
 * @param context The API client's supplied context value.
 *
 * @see `MSACCrashesCallbacks`
 * @see `[MSACCrashes setCrashCallbacks:]`
 */
typedef void (*MSACCrashesPostCrashSignalCallback)(void *context);

/**
 * This structure contains callbacks supported by `MSACCrashes` to allow the host
 * application to perform additional tasks prior to program termination after a
 * crash has occurred.
 *
 * @see `MSACCrashesPostCrashSignalCallback`
 * @see `[MSACCrashes setCrashCallbacks:]`
 */
typedef struct MSACCrashesCallbacks {

  /**
   * An arbitrary user-supplied context value. This value may be NULL.
   */
  void *context;

  /**
   * The callback used to report caught signal information.
   */
  MSACCrashesPostCrashSignalCallback handleSignal;
} MSACCrashesCallbacks;

@property(nonatomic, assign, getter=isMachExceptionHandlerEnabled) BOOL enableMachExceptionHandler;

/**
 * A list containing all crash files that currently stored on disk for this app.
 */
@property(nonatomic, copy) NSMutableArray *crashFiles;

/**
 * The path component directory where all crash reports are stored.
 */
@property(nonatomic, copy) NSString *crashesPathComponent;

/**
 * The directory where all buffered logs are stored.
 */
@property(nonatomic, copy) NSString *logBufferPathComponent;

/**
 * A path component that's used to indicate that a crash which occurred in the
 * last session is currently written to disk.
 */
@property(nonatomic, copy) NSString *analyzerInProgressFilePathComponent;

/**
 * The object implements the protocol defined in `MSACCrashesDelegate`.
 * @see MSACCrashesDelegate
 */
@property(nonatomic, weak) id<MSACCrashesDelegate> delegate;

/**
 * The `PLCrashReporter` instance used for crash detection.
 */
@property(nonatomic) PLCrashReporter *plCrashReporter;

/**
 * The exception handler used by the crashes service.
 */
@property(nonatomic) NSUncaughtExceptionHandler *exceptionHandler;

/**
 * Temporary storage for crashes logs to handle user confirmation and callbacks.
 */
@property NSMutableArray *unprocessedLogs;
@property NSMutableArray *unprocessedReports;
@property NSMutableArray *unprocessedFilePaths;

/**
 * Custom user confirmation handler.
 */
@property MSACUserConfirmationHandler userConfirmationHandler;

/**
 * The start time of the application.
 */
@property(nonatomic) NSDate *appStartTime;

/**
 * Delete all data in crashes directory.
 */
- (void)deleteAllFromCrashesDirectory;

/**
 * Determine whether the error report should be processed or not.
 *
 * @param errorReport An error report.
 * @return YES if it should process, otherwise NO.
 */
- (BOOL)shouldProcessErrorReport:(MSACErrorReport *)errorReport;

/**
 * Creates log buffer to buffer logs which will be saved in an async-safe manner
 * at crash time. The buffer makes sure we don't lose any logs at crash time.
 * This method creates 20 files that will be used to buffer 20 logs.
 * The files will only be created once and not recreated from scratch every time
 * MSACCrashes is initialized.
 */
- (void)setupLogBuffer;

/**
 * Sends crashes when given MSACUserConfirmationSend.
 */
- (void)notifyWithUserConfirmation:(MSACUserConfirmation)userConfirmation;

/**
 * Does not delete the files for our log buffer but "resets" them to be empty.
 * For this, it actually overwrites the old file with an empty copy of the
 * original one. The reason why we are not truly deleting the files is that they
 * need to exist at crash time.
 */
- (void)emptyLogBufferFiles;

/**
 * Method to reset the singleton when running unit tests only. So calling
 * sharedInstance returns a fresh instance.
 */
+ (void)resetSharedInstance;

@end
