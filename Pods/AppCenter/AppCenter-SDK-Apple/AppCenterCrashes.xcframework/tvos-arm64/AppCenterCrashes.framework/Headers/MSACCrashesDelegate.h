// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@class MSACCrashes;
@class MSACErrorReport;
@class MSACErrorAttachmentLog;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(CrashesDelegate)
@protocol MSACCrashesDelegate <NSObject>

@optional

/**
 * Callback method that will be called before processing errors.
 *
 * @param crashes The instance of MSACCrashes.
 * @param errorReport The errorReport that will be sent.
 *
 * @discussion Crashes will send logs to the server or discard/delete logs based on this method's return value.
 */
- (BOOL)crashes:(MSACCrashes *)crashes shouldProcessErrorReport:(MSACErrorReport *)errorReport NS_SWIFT_NAME(crashes(_:shouldProcess:));

/**
 * Callback method that will be called before each error will be send to the server.
 *
 * @param crashes The instance of MSACCrashes.
 * @param errorReport The errorReport that will be sent.
 *
 * @discussion Use this callback to display custom UI while crashes are sent to the server.
 */
- (void)crashes:(MSACCrashes *)crashes willSendErrorReport:(MSACErrorReport *)errorReport;

/**
 * Callback method that will be called after the SDK successfully sent an error report to the server.
 *
 * @param crashes The instance of MSACCrashes.
 * @param errorReport The errorReport that App Center sent.
 *
 * @discussion Use this method to hide your custom UI.
 */
- (void)crashes:(MSACCrashes *)crashes didSucceedSendingErrorReport:(MSACErrorReport *)errorReport;

/**
 * Callback method that will be called in case the SDK was unable to send an error report to the server.
 *
 * @param crashes The instance of MSACCrashes.
 * @param errorReport The errorReport that App Center tried to send.
 * @param error The error that occurred.
 */
- (void)crashes:(MSACCrashes *)crashes didFailSendingErrorReport:(MSACErrorReport *)errorReport withError:(nullable NSError *)error;

/**
 * Method to get the attachments associated to an error report.
 *
 * @param crashes The instance of MSACCrashes.
 * @param errorReport The errorReport associated with the returned attachments.
 *
 * @return The attachments associated with the given error report or nil if the error report doesn't have any attachments.
 *
 * @discussion Implement this method if you want attachments to the given error report.
 */
- (nullable NSArray<MSACErrorAttachmentLog *> *)attachmentsWithCrashes:(MSACCrashes *)crashes forErrorReport:(MSACErrorReport *)errorReport;

@end

NS_ASSUME_NONNULL_END
