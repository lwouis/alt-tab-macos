// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <objc/runtime.h>

#import "MSACAppCenterInternal.h"
#import "MSACApplicationForwarder.h"
#import "MSACCrashesInternal.h"
#import "MSACCrashesPrivate.h"
#import "MSACUtility+Application.h"

static NSString *const kMSACAppCenterApplicationForwarderEnabledKey = @"AppCenterApplicationForwarderEnabled";

static BOOL isApplicationForwarderEnabled() {
  NSNumber *forwarderEnabled = [NSBundle.mainBundle objectForInfoDictionaryKey:kMSACAppCenterApplicationForwarderEnabledKey];
  return forwarderEnabled ? [forwarderEnabled boolValue] : YES;
}

#if TARGET_OS_OSX

/**
 * The flag to allow crashing on uncaught exceptions thrown on the main thread.
 */
static NSString *const kMSACCrashOnExceptionsKey = @"NSApplicationCrashOnExceptions";

static BOOL isCrashOnExceptionsEnabled() {

  // We use NSUserDefaults here instead of MSACAppCenterUserDefaults, because
  // we should use system user defaults for system keys.
  // MSACAppCenterUserDefaults prepends all the keys with "MSAppCenter" prefix.
  NSNumber *crashOnExceptions = [[NSUserDefaults standardUserDefaults] objectForKey:kMSACCrashOnExceptionsKey];
  return [crashOnExceptions boolValue];
}

/*
 * On OS X runtime, not all uncaught exceptions end in a custom `NSUncaughtExceptionHandler`.
 * In addition "sometimes" exceptions don't even cause the app to crash, depending on where and
 * when they happen.
 *
 * Here are the known scenarios:
 *
 *   1. Custom `NSUncaughtExceptionHandler` don't start working until after `NSApplication` has finished
 *      calling all of its delegate methods!
 *
 *      Example:
 *        - (void)applicationDidFinishLaunching:(NSNotification *)note {
 *          ...
 *          [NSException raise:@"ExceptionAtStartup" format:@"This will not be recognized!"];
 *          ...
 *        }
 *
 *
 *   2. The default `NSUncaughtExceptionHandler` in `NSApplication` only logs exceptions to the console and
 *      ends their processing. Resulting in exceptions that occur in the `NSApplication` "scope" not
 *      occurring in a registered custom `NSUncaughtExceptionHandler`.
 *
 *      Example:
 *        - (void)applicationDidFinishLaunching:(NSNotification *)note {
 *          ...
 *           [self performSelector:@selector(delayedException) withObject:nil afterDelay:5];
 *          ...
 *        }
 *
 *        - (void)delayedException {
 *          NSArray *array = [NSArray array];
 *          [array objectAtIndex:23];
 *        }
 *
 *   3. Any exceptions occurring in IBAction or other GUI does not even reach the NSApplication default
 *      UncaughtExceptionHandler.
 *
 *      Example:
 *        - (IBAction)doExceptionCrash:(id)sender {
 *          NSArray *array = [NSArray array];
 *          [array objectAtIndex:23];
 *        }
 *
 *
 * Solution A:
 *
 *   Implement `NSExceptionHandler` and set the `ExceptionHandlingMask` to `NSLogAndHandleEveryExceptionMask`
 *
 *   Benefits:
 *
 *     1. Solves all of the above scenarios.
 *
 *     2. Clean solution using a standard Cocoa System specifically meant for this purpose.
 *
 *     3. Safe. Doesn't use private API.
 *
 *   Problems:
 *
 *     1. To catch all exceptions the `NSExceptionHandlers` mask has to include `NSLogOtherExceptionMask` and
 *        `NSHandleOtherExceptionMask`. But this will result in @catch blocks to be called after the exception
 *        handler processed the exception and likely lets the app crash and create a crash report.
 *        This makes the @catch block basically not work at all.
 *
 *     2. If anywhere in the app a custom `NSUncaughtExceptionHandler` will be registered, e.g. in a closed source
 *        library the developer has to use, the complete mechanism will stop working.
 *
 *     3. Not clear if this solves all scenarios there can be.
 *
 *     4. Requires to adjust PLCrashReporter not to register its `NSUncaughtExceptionHandler` which is not a good idea,
 *        since it would require the `NSExceptionHandler` would catch *all* exceptions and that would cause
 *        PLCrashReporter to stop all running threads every time an exception occurs even if it will be handled right
 *        away, e.g. by a system framework.
 *
 *
 * Solution B:
 *
 *   Overwrite and extend specific methods of `NSApplication`. Can be implemented via subclassing NSApplication or
 *   by using a category.
 *
 *   Benefits:
 *
 *     1. Solves scenarios 2 (by overwriting `reportException:`) and 3 (by overwriting `sendEvent:`).
 *
 *     2. Subclassing approach isn't enforcing the mechanism onto apps and lets developers opt-in.
 *        (Category approach would enforce it and rather be a problem of this solution.)
 *
 *     3. Safe. Doesn't use private API.
 *
 *  Problems:
 *
 *     1. Does not automatically solve scenario 1. Developer would have to put all that code into @try @catch blocks.
 *
 *     2. Not a clean implementation, rather feels like a workaround.
 *
 *     3. Not clear if this solves all scenarios there can be.
 *
 *
 * References:
 *   https://developer.apple.com/library/mac/documentation/cocoa/Conceptual/Exceptions/Tasks/ControllingAppResponse.html#//apple_ref/doc/uid/20000473-BBCHGJIJ
 *   http://stackoverflow.com/a/4199717/474794
 *   http://stackoverflow.com/a/3419073/474794
 *   http://macdevcenter.com/pub/a/mac/2007/07/31/understanding-exceptions-and-handlers-in-cocoa.html
 *
 */

#pragma mark Report Exception

typedef void (*MSACReportExceptionImp)(id, SEL, NSException *);
static MSACReportExceptionImp reportExceptionOriginalImp;

static void ms_reportException(id self, SEL _cmd, NSException *exception) {
  [MSACCrashes applicationDidReportException:exception];

  // Forward to the original implementation.
  reportExceptionOriginalImp(self, _cmd, exception);
}

static void swizzleReportException() {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method originalMethod = class_getInstanceMethod([NSApplication class], @selector(reportException:));
    reportExceptionOriginalImp = (MSACReportExceptionImp)method_setImplementation(originalMethod, (IMP)ms_reportException);
    MSACLogDebug([MSACCrashes logTag], @"Selector 'reportException:' of class 'NSApplication' is swizzled.");
  });
}

#pragma mark Send Event

typedef void (*MSACSendEventImp)(id, SEL, NSEvent *);
static MSACSendEventImp sendEventOriginalImp;

static void ms_sendEvent(id self, SEL _cmd, NSEvent *event) {
  @try {

    // Forward to the original implementation.
    sendEventOriginalImp(self, _cmd, event);
  } @catch (NSException *exception) {
    ms_reportException(self, @selector(reportException:), exception);
  }
}

static void swizzleSendEvent() {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    Method originalMethod = class_getInstanceMethod([NSApplication class], @selector(sendEvent:));
    sendEventOriginalImp = (MSACSendEventImp)method_setImplementation(originalMethod, (IMP)ms_sendEvent);
    MSACLogDebug([MSACCrashes logTag], @"Selector 'sendEvent:' of class 'NSApplication' is swizzled.");
  });
}

#endif

@implementation MSACApplicationForwarder

+ (void)registerForwarding {
  if (isApplicationForwarderEnabled()) {
    MSACLogDebug([MSACCrashes logTag], @"Application forwarder for info.plist key '%@' enabled. It may use swizzling.",
                 kMSACAppCenterApplicationForwarderEnabledKey);
  } else {
    MSACLogDebug([MSACCrashes logTag], @"Application forwarder for info.plist key '%@' disabled. It won't use swizzling.",
                 kMSACAppCenterApplicationForwarderEnabledKey);
    return;
  }
#if TARGET_OS_OSX
  if (isCrashOnExceptionsEnabled()) {

    /*
     * Solution for Scenario 2:
     *
     * Catch all exceptions that are being logged to the console and forward them to our
     * custom UncaughtExceptionHandler.
     */
    swizzleReportException();

    /*
     * Solution for Scenario 3:
     *
     * Exceptions that happen inside an IBAction implementation do not trigger a call to
     * [NSApplication reportException:] and it does not trigger a registered UncaughtExceptionHandler
     * Hence we need to catch these ourselves, e.g. by overwriting sendEvent: as done right here.
     *
     * On 64bit systems the @try @catch block doesn't even cost any performance.
     */
    swizzleSendEvent();
  } else {
    MSACLogInfo([MSACCrashes logTag],
                @"Catching uncaught exceptions thrown on the main thread disabled. "
                @"Set `%@` flag before SDK initialization, to allow crash on uncaught exceptions and the SDK can report them.",
                kMSACCrashOnExceptionsKey);
  }
#endif
}

@end
