// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@class MSCrashes;
@class MSErrorReport;
@class MSErrorAttachmentLog;

@protocol MSCrashesDelegate <NSObject>

@optional

/**
 * Callback method that will be called before processing errors.
 *
 * @param crashes The instance of MSCrashes.
 * @param errorReport The errorReport that will be sent.
 *
 * @discussion Crashes will send logs to the server or discard/delete logs based on this method's return value.
 */
- (BOOL)crashes:(MSCrashes *)crashes shouldProcessErrorReport:(MSErrorReport *)errorReport;

/**
 * Callback method that will be called before each error will be send to the server.
 *
 * @param crashes The instance of MSCrashes.
 * @param errorReport The errorReport that will be sent.
 *
 * @discussion Use this callback to display custom UI while crashes are sent to the server.
 */
- (void)crashes:(MSCrashes *)crashes willSendErrorReport:(MSErrorReport *)errorReport;

/**
 * Callback method that will be called in case the SDK was unable to send an error report to the server.
 *
 * @param crashes The instance of MSCrashes.
 * @param errorReport The errorReport that App Center sent.
 *
 * @discussion Use this method to hide your custom UI.
 */
- (void)crashes:(MSCrashes *)crashes didSucceedSendingErrorReport:(MSErrorReport *)errorReport;

/**
 * Callback method that will be called in case the SDK was unable to send an error report to the server.
 *
 * @param crashes The instance of MSCrashes.
 * @param errorReport The errorReport that App Center tried to send.
 * @param error The error that occurred.
 */
- (void)crashes:(MSCrashes *)crashes didFailSendingErrorReport:(MSErrorReport *)errorReport withError:(NSError *)error;

/**
 * Method to get the attachments associated to an error report.
 *
 * @param crashes The instance of MSCrashes.
 * @param errorReport The errorReport associated with the returned attachments.
 *
 * @return The attachments associated with the given error report or nil if the error report doesn't have any attachments.
 *
 * @discussion Implement this method if you want attachments to the given error report.
 */
- (NSArray<MSErrorAttachmentLog *> *)attachmentsWithCrashes:(MSCrashes *)crashes forErrorReport:(MSErrorReport *)errorReport;

@end
