// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if __has_include(<AppCenterCrashes/MSACCrashHandlerSetupDelegate.h>)
#import <AppCenterCrashes/MSACCrashHandlerSetupDelegate.h>
#else
#import "MSACCrashHandlerSetupDelegate.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@class MSACErrorReport;
@class MSACErrorAttachmentLog;
@class MSACException;

/**
 * This general class allows wrappers to supplement the Crashes SDK with their own behavior.
 */
NS_SWIFT_NAME(WrapperCrashesHelper)
@interface MSACWrapperCrashesHelper : NSObject

/**
 * The crash handler setup delegate.
 *
 */
@property(class, nonatomic) _Nullable id<MSACCrashHandlerSetupDelegate> crashHandlerSetupDelegate;

/**
 * Gets the crash handler setup delegate.
 *
 * @deprecated
 *
 * @return The delegate being used by Crashes.
 */
+ (id<MSACCrashHandlerSetupDelegate>)getCrashHandlerSetupDelegate DEPRECATED_MSG_ATTRIBUTE("Use crashHandlerSetupDelegate instead");

/**
 * Enables or disables automatic crash processing. Passing NO causes SDK not to send reports immediately, even if "Always Send" is true.
 */
@property(class, nonatomic) BOOL automaticProcessing;

/**
 * Gets a list of unprocessed crash reports. Will block until the service starts.
 *
 * @return An array of unprocessed error reports.
 */
@property(class, readonly, nonatomic) NSArray<MSACErrorReport *> *unprocessedCrashReports;

/**
 * Resumes processing for a given subset of the unprocessed reports.
 *
 * @param filteredIds An array containing the errorId/incidentIdentifier of each report that should be sent.
 *
 * @return YES if should "Always Send" is true.
 */
+ (BOOL)sendCrashReportsOrAwaitUserConfirmationForFilteredIds:(NSArray<NSString *> *)filteredIds;

/**
 * Sends error attachments for a particular error report.
 *
 * @param errorAttachments An array of error attachments that should be sent.
 * @param incidentIdentifier The identifier of the error report that the attachments will be associated with.
 */
+ (void)sendErrorAttachments:(NSArray<MSACErrorAttachmentLog *> *)errorAttachments withIncidentIdentifier:(NSString *)incidentIdentifier;

/**
 * Track handled exception directly as model form.
 * This API is used by wrapper SDKs.
 *
 * @param exception model form exception.
 * @param properties dictionary of properties.
 * @param attachments a list of attachments.
 *
 * @return handled error ID.
 */
+ (nullable NSString *)trackModelException:(MSACException *)exception
                            withProperties:(nullable NSDictionary<NSString *, NSString *> *)properties
                           withAttachments:(nullable NSArray<MSACErrorAttachmentLog *> *)attachments;

/**
 * Get a generic error report representation for an handled exception.
 * This API is used by wrapper SDKs.
 *
 * @param errorID handled error ID.
 *
 * @return an error report.
 */
+ (MSACErrorReport *)buildHandledErrorReportWithErrorID:(NSString *)errorID;

@end

NS_ASSUME_NONNULL_END
