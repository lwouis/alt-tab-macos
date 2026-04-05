// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACWrapperCrashesHelper.h"
#import "MSACCrashesInternal.h"
#import "MSACErrorReportPrivate.h"

@interface MSACWrapperCrashesHelper ()

@property(weak, nonatomic) id<MSACCrashHandlerSetupDelegate> crashHandlerSetupDelegate;

@end

@implementation MSACWrapperCrashesHelper

/**
 * Gets the singleton instance.
 */
+ (instancetype)sharedInstance {
  static MSACWrapperCrashesHelper *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[MSACWrapperCrashesHelper alloc] init];
  });
  return sharedInstance;
}

+ (void)setCrashHandlerSetupDelegate:(id<MSACCrashHandlerSetupDelegate>)delegate {
  [[MSACWrapperCrashesHelper sharedInstance] setCrashHandlerSetupDelegate:delegate];
}

+ (id<MSACCrashHandlerSetupDelegate>)crashHandlerSetupDelegate {
  return [MSACWrapperCrashesHelper sharedInstance].crashHandlerSetupDelegate;
}

+ (id<MSACCrashHandlerSetupDelegate>)getCrashHandlerSetupDelegate {
  return [MSACWrapperCrashesHelper sharedInstance].crashHandlerSetupDelegate;
}

/**
 * Enables or disables automatic crash processing. Setting to 'NO'causes SDK not to send reports immediately, even if ALWAYS_SEND is set.
 */
+ (void)setAutomaticProcessing:(BOOL)automaticProcessing {
  [[MSACCrashes sharedInstance] setAutomaticProcessingEnabled:automaticProcessing];
}

+ (BOOL)automaticProcessing {
  return [MSACCrashes sharedInstance].isAutomaticProcessingEnabled;
}

/**
 * Gets a list of unprocessed crash reports.
 */
+ (NSArray<MSACErrorReport *> *)unprocessedCrashReports {
  return [[MSACCrashes sharedInstance] unprocessedCrashReports];
}

/**
 * Resumes processing for a given subset of the unprocessed reports. Returns YES if should "AlwaysSend".
 */
+ (BOOL)sendCrashReportsOrAwaitUserConfirmationForFilteredIds:(NSArray<NSString *> *)filteredIds {
  return [[MSACCrashes sharedInstance] sendCrashReportsOrAwaitUserConfirmationForFilteredIds:filteredIds];
}

/**
 * Sends error attachments for a particular error report.
 */
+ (void)sendErrorAttachments:(NSArray<MSACErrorAttachmentLog *> *)errorAttachments withIncidentIdentifier:(NSString *)incidentIdentifier {
  [[MSACCrashes sharedInstance] sendErrorAttachments:errorAttachments withIncidentIdentifier:incidentIdentifier];
}

+ (MSACErrorReport *)buildHandledErrorReportWithErrorID:(NSString *)errorID {
  return [[MSACCrashes sharedInstance] buildHandledErrorReportWithErrorID:errorID];
}

@end
