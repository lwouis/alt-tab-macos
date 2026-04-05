// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#if __has_include(<AppCenter/MSACServiceAbstract.h>)
#import <AppCenter/MSACServiceAbstract.h>
#else
#import "MSACServiceAbstract.h"
#endif

#if __has_include(<AppCenterCrashes/MSACErrorReport.h>)
#import <AppCenterCrashes/MSACErrorReport.h>
#else
#import "MSACErrorReport.h"
#endif

@class MSACCrashesDelegate;
@class MSACExceptionModel;
@class MSACErrorAttachmentLog;

/**
 * Custom block that handles the alert that prompts the user whether crash reports need to be processed or not.
 *
 * @return Returns YES to discard crash reports, otherwise NO.
 */
typedef BOOL (^MSACUserConfirmationHandler)(NSArray<MSACErrorReport *> *_Nonnull errorReports) NS_SWIFT_NAME(UserConfirmationHandler);

/**
 * Error Logging status.
 */
typedef NS_ENUM(NSUInteger, MSACErrorLogSetting) {

  /**
   * Crash reporting is disabled.
   */
  MSACErrorLogSettingDisabled = 0,

  /**
   * User is asked each time before sending error logs.
   */
  MSACErrorLogSettingAlwaysAsk = 1,

  /**
   * Each error log is send automatically.
   */
  MSACErrorLogSettingAutoSend = 2
} NS_SWIFT_NAME(ErrorLogSetting);

/**
 * Crash Manager alert user input.
 */
typedef NS_ENUM(NSUInteger, MSACUserConfirmation) {

  /**
   * User chose not to send the crash report.
   */
  MSACUserConfirmationDontSend = 0,

  /**
   * User wants the crash report to be sent.
   */
  MSACUserConfirmationSend = 1,

  /**
   * User wants to send all error logs.
   */
  MSACUserConfirmationAlways = 2
} NS_SWIFT_NAME(UserConfirmation);

@protocol MSACCrashesDelegate;

NS_SWIFT_NAME(Crashes)
@interface MSACCrashes : MSACServiceAbstract

/**
 * Track handled error.
 *
 * @param error error.
 * @param properties dictionary of properties.
 * @param attachments a list of attachments.
 *
 * @return handled error ID.
 */
+ (NSString *_Nonnull)trackError:(NSError *_Nonnull)error
                  withProperties:(nullable NSDictionary<NSString *, NSString *> *)properties
                     attachments:(nullable NSArray<MSACErrorAttachmentLog *> *)attachments NS_SWIFT_NAME(trackError(_:properties:attachments:));

/**
 * Track handled exception from custom exception model.
 *
 * @param exception custom model exception.
 * @param properties dictionary of properties.
 * @param attachments a list of attachments.
 *
 * @return handled error ID.
 */
+ (NSString *_Nonnull)trackException:(MSACExceptionModel *_Nonnull)exception
                      withProperties:(nullable NSDictionary<NSString *, NSString *> *)properties
                         attachments:(nullable NSArray<MSACErrorAttachmentLog *> *)attachments NS_SWIFT_NAME(trackException(_:properties:attachments:));

///-----------------------------------------------------------------------------
/// @name Testing Crashes Feature
///-----------------------------------------------------------------------------

/**
 * Lets the app crash for easy testing of the SDK.
 *
 * The best way to use this is to trigger the crash with a button action.
 *
 * Make sure not to let the app crash in `applicationDidFinishLaunching` or any other startup method! Since otherwise the app would crash
 * before the SDK could process it.
 *
 * Note that our SDK provides support for handling crashes that happen early on startup. Check the documentation for more information on how
 * to use this.
 *
 * If the SDK detects an App Store environment, it will _NOT_ cause the app to crash!
 */
+ (void)generateTestCrash;

///-----------------------------------------------------------------------------
/// @name Helpers
///-----------------------------------------------------------------------------

/**
 * Check if the app has crashed in the last session.
 *
 * @return Returns YES is the app has crashed in the last session.
 */
@property(class, readonly, nonatomic) BOOL hasCrashedInLastSession;

/**
 * Check if the app received memory warning in the last session.
 *
 * @return Returns YES is the app received memory warning in the last session.
 */
@property(class, readonly, nonatomic) BOOL hasReceivedMemoryWarningInLastSession;

/**
 * Provides details about the crash that occurred in the last app session
 */
@property(class, nullable, readonly, nonatomic) MSACErrorReport *lastSessionCrashReport;

#if TARGET_OS_OSX || TARGET_OS_MACCATALYST
/**
 * Callback for report exception.
 *
 * NOTE: This method should be called only if you explicitly disabled swizzling for it.
 *
 * On OS X runtime, not all uncaught exceptions end in a custom `NSUncaughtExceptionHandler`.
 * Forward exception from overrided `[NSApplication reportException:]` to catch additional exceptions.
 */
+ (void)applicationDidReportException:(NSException *_Nonnull)exception;
#endif

///-----------------------------------------------------------------------------
/// @name Configuration
///-----------------------------------------------------------------------------

#if !TARGET_OS_TV
/**
 * Disable the Mach exception server.
 *
 * By default, the SDK uses the Mach exception handler to catch fatal signals, e.g. stack overflows, via a Mach exception server. If you
 * want to disable the Mach exception handler, you should call this method _BEFORE_ starting the SDK. Your typical setup code would look
 * like this:
 *
 * `[MSACCrashes disableMachExceptionHandler]`;
 * `[MSACAppCenter start:@"YOUR_APP_ID" withServices:@[[MSACCrashes class]]];`
 *
 * or if you are using Swift:
 *
 * `MSACCrashes.disableMachExceptionHandler()`
 * `MSACAppCenter.start("YOUR_APP_ID", withServices: [MSACAnalytics.self, MSACCrashes.self])`
 *
 * tvOS does not support the Mach exception handler, thus crashes that are caused by stack overflows cannot be detected. As a result,
 * disabling the Mach exception server is not available in the tvOS SDK.
 *
 * @discussion It can be useful to disable the Mach exception handler when you are debugging the Crashes service while developing,
 * especially when you attach the debugger to your application after launch.
 */
+ (void)disableMachExceptionHandler;
#endif

/**
 * Set the delegate
 * Defines the class that implements the optional protocol `MSACCrashesDelegate`.
 *
 * @see MSACCrashesDelegate
 */
@property(class, nonatomic, weak) id<MSACCrashesDelegate> _Nullable delegate;

/**
 * Set a user confirmation handler that is invoked right before processing crash reports to determine whether sending crash reports or not.
 *
 * @see MSACUserConfirmationHandler
 */
@property(class, nonatomic) MSACUserConfirmationHandler _Nullable userConfirmationHandler;

/**
 * Notify SDK with a confirmation to handle the crash report.
 *
 * @param userConfirmation A user confirmation.
 *
 * @see MSACUserConfirmation.
 */
+ (void)notifyWithUserConfirmation:(MSACUserConfirmation)userConfirmation;

@end
