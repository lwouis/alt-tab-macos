//
//  SPUStandardUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SPUStandardUserDriver.h"
#import "SPUStandardUserDriverDelegate.h"
#import "SPUGentleUserDriverReminders.h"
#import "SUAppcastItem.h"
#import "SUVersionDisplayProtocol.h"
#import "SUHost.h"
#import "SUUpdatePermissionPrompt.h"
#import "SUStatusController.h"
#import "SUUpdateAlert.h"
#import "SULocalizations.h"
#import "SUApplicationInfo.h"
#import "SPUUserUpdateState.h"
#import "SUErrors.h"
#import "SPUInstallationType.h"
#import "SPUStandardVersionDisplay.h"
#import "SULog.h"
#import "SPUNoUpdateFoundInfo.h"
#import "SPUUpdaterSettings.h"
#import "SPUUpdaterSettings+Debug.h"

#include <time.h>
#include <mach/mach_time.h>
#import <IOKit/pwr_mgt/IOPMLib.h>


#import <AppKit/AppKit.h>

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 140000
@interface NSApplication (ActivationAPIs)
- (void)activate;
@end
#endif

@interface SPUStandardUserDriver () <SPUGentleUserDriverReminders>

// Note: we expose a private interface for activeUpdateAlert property in SPUStandardUserDriver+Private.h as NSWindowController
@property (nonatomic, readonly, nullable) NSWindowController *activeUpdateAlert;

@end

@implementation SPUStandardUserDriver
{
    void (^_retryTerminatingApplication)(void);
    void (^_installUpdateHandler)(SPUUserUpdateChoice);
    void (^_cancellation)(void);
    
    SUHost *_host;
    // We must store the oldHostName before the host is potentially replaced
    // because we may use this property after update has been installed
    NSString *_oldHostName;
    NSURL *_oldHostBundleURL;
    
    id<NSObject> _applicationBecameActiveAfterUpdateAlertBecameKeyObserver;
    NSValue *_updateAlertWindowFrameValue;
    SUStatusController *_checkingController;
    
    SUUpdateAlert *_activeUpdateAlert;
    SPUUpdaterSettings *_updaterSettings;
    
    SUStatusController *_statusController;
    SUUpdatePermissionPrompt *_permissionPrompt;
    
    __weak id <SPUStandardUserDriverDelegate> _delegate;
    
    mach_timebase_info_data_t _timebaseInfo;
    
    uint64_t _expectedContentLength;
    uint64_t _bytesDownloaded;
    double _timeSinceOpportuneUpdateNotice;
    
    BOOL _updateAlertWindowWasInactive;
    BOOL _loggedGentleUpdateReminderWarning;
    BOOL _regularApplicationUpdate;
    BOOL _updateReceivedUserAttention;
}

@synthesize activeUpdateAlert = _activeUpdateAlert;

#pragma mark Birth

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(nullable id<SPUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        _updaterSettings = [[SPUUpdaterSettings alloc] initWithHostBundle:hostBundle];
        _oldHostName = _host.name;
        _oldHostBundleURL = hostBundle.bundleURL;
        _delegate = delegate;
        
        kern_return_t timebaseInfoResult = mach_timebase_info(&_timebaseInfo);
        if (timebaseInfoResult != KERN_SUCCESS) {
            SULog(SULogLevelError, @"Error: failed to fill mach_timebase_info() with error %d", timebaseInfoResult);
            
            _timebaseInfo.numer = 0;
            _timebaseInfo.denom = 0;
        }
    }
    return self;
}

- (double)currentTime SPU_OBJC_DIRECT
{
    if (_timebaseInfo.denom > 0) {
        return (double)(mach_absolute_time() * _timebaseInfo.numer) / (double)_timebaseInfo.denom;
    } else {
        return 0.0;
    }
}

// This private method is used by SPUUpdater for resetting the opportune time to show an update notice in utmost focus
- (void)resetTimeSinceOpportuneUpdateNotice
{
    _timeSinceOpportuneUpdateNotice = [self currentTime];
}

#pragma mark Update Permission

- (void)_activateApplication SPU_OBJC_DIRECT
{
    if (@available(macOS 14, *)) {
        [NSApp activate];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    assert(NSThread.isMainThread);
    
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [self _activateApplication];
    }
    
    __weak __typeof__(self) weakSelf = self;
    _permissionPrompt = [[SUUpdatePermissionPrompt alloc] initPromptWithHost:_host request:request reply:^(SUUpdatePermissionResponse *response) {
        reply(response);
        
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_permissionPrompt = nil;
        }
    }];
    
    [_permissionPrompt showWindow:nil];
}

#pragma mark Update Alert Focus

// This private method is used by SPUUpdater when scheduling for update checks
- (void)logGentleScheduledUpdateReminderWarningIfNeeded
{
    id<SPUStandardUserDriverDelegate> delegate = _delegate;
    if (!_loggedGentleUpdateReminderWarning && (![delegate respondsToSelector:@selector(supportsGentleScheduledUpdateReminders)] || !delegate.supportsGentleScheduledUpdateReminders)) {
        BOOL isBackgroundApp = [SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]];
        if (isBackgroundApp) {
            SULog(SULogLevelError, @"Warning: Background app automatically schedules for update checks but does not implement gentle reminders. As a result, users may not take notice to update alerts that show up in the background. Please visit https://sparkle-project.org/documentation/gentle-reminders for more information. This warning will only be logged once.");
            
            _loggedGentleUpdateReminderWarning = YES;
        }
    }
}

// updateItem should be non-nil when showing an update for first time for scheduled updates
// If appcastItem is != nil, then state must be != nil
- (void)setUpActiveUpdateAlertForScheduledUpdate:(SUAppcastItem * _Nullable)updateItem state:(SPUUserUpdateState * _Nullable)state SPU_OBJC_DIRECT
{
    // Make sure the window is loaded in any case
    [_activeUpdateAlert window];
    
    [self _removeApplicationBecomeActiveObserver];
    
    if (updateItem == nil) {
        // This is a user initiated check or a check to bring the already shown update back in focus
        if (![NSApp isActive]) {
            // If the user initiated an update check, we should make the app active,
            // regardless if it's a background running app or not
            [self _activateApplication];
        }
        
        [_activeUpdateAlert showWindow:nil];
        [_activeUpdateAlert setInstallButtonFocus:YES];
    } else {
        // Handle scheduled update check
        uint64_t timeElapsedSinceOpportuneUpdateNotice = (uint64_t)([self currentTime] - _timeSinceOpportuneUpdateNotice);
        
        // Give scheduled update alerts priority if 3 or less seconds have passed since our last opportune time
        BOOL appNearUpdaterInitialization = (timeElapsedSinceOpportuneUpdateNotice <= 3000000000ULL);
        
        // We will always show an update alert at the right time
        [_activeUpdateAlert setInstallButtonFocus:YES];
        
        // If the delegate doesn't override our behavior:
        // For regular applications, only show the update alert if the app is active and if it's an an opportune time, otherwise, we'll wait until the app becomes active again.
        // For background applications, if the app is active, we will show the update window ordered back.
        // If the app is inactive, we'll show the update alert in the background behind other running apps
        // But we are near app launch, we will activate the app and show the alert as key
        BOOL backgroundApp = [SUApplicationInfo isBackgroundApplication:NSApp];
        BOOL driverShowingUpdateNow;
        BOOL immediateFocus;
        BOOL showingUpdateInBack;
        BOOL activatingApp;
        if ([NSApp isActive]) {
            BOOL systemHasBeenIdle;
            {
                // If the system has been inactive for several minutes, allow the update alert to show up immediately. We assume it's likely the user isn't at their computer in this case.
                // Note this is not done for background running applications.
                CFTimeInterval timeSinceLastEvent;
                if (!appNearUpdaterInitialization && !backgroundApp) {
                    timeSinceLastEvent = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType);
                    
                    NSTimeInterval scheduledUpdateIdleEventLeewayInterval = _updaterSettings.standardUIScheduledUpdateIdleEventLeewayInterval;
                    
                    if (timeSinceLastEvent >= scheduledUpdateIdleEventLeewayInterval) {
                        // Make sure there's no active power management assertions preventing
                        // the display from sleeping by the current application.
                        // If there is, then the app may still actively be in use
                        CFDictionaryRef cfAssertions = NULL;
                        if (IOPMCopyAssertionsByProcess(&cfAssertions) == kIOReturnSuccess) {
                            NSDictionary<NSNumber *, NSArray<NSDictionary<NSString *, id> *> *> *assertions = CFBridgingRelease(cfAssertions);
                            
                            pid_t currentProcessIdentifier = NSRunningApplication.currentApplication.processIdentifier;
                            
                            NSNumber *processIdentifierKey = @(currentProcessIdentifier);
                            NSArray<NSDictionary<NSString *, id> *> *currentProcessAssertions = assertions[processIdentifierKey];
                            
                            BOOL foundNoDisplaySleepAssertion = NO;
                            for (NSDictionary<NSString *, id> *assertion in currentProcessAssertions) {
                                NSString *assertionType = assertion[(NSString *)kIOPMAssertionTypeKey];
                                NSNumber *assertionLevel = assertion[(NSString *)kIOPMAssertionLevelKey];
                                if ([assertionType isEqualToString:(NSString *)kIOPMAssertionTypeNoDisplaySleep] && [assertionLevel isEqual:@(kIOPMAssertionLevelOn)]) {
                                    
                                    foundNoDisplaySleepAssertion = YES;
                                    break;
                                }
                            }
                            
                            systemHasBeenIdle = !foundNoDisplaySleepAssertion;
                        } else {
                            systemHasBeenIdle = NO;
                        }
                    } else {
                        systemHasBeenIdle = NO;
                    }
                } else {
                    systemHasBeenIdle = NO;
                }
            }
            
            if (appNearUpdaterInitialization || systemHasBeenIdle) {
                driverShowingUpdateNow = YES;
                immediateFocus = YES;
                showingUpdateInBack = NO;
                activatingApp = backgroundApp;
            } else {
                driverShowingUpdateNow = backgroundApp;
                immediateFocus = NO;
                // If there is a key window active in the app, show the update alert behind other windows
                showingUpdateInBack = backgroundApp && ([NSApp keyWindow] != nil);
                activatingApp = NO;
            }
        } else {
            // For regular applications, we will show the update alert when the user comes back to the app
            // For background applications, we will show the update alert right away but in the background,
            // unless focus is requested
            if (!backgroundApp) {
                driverShowingUpdateNow = NO;
                immediateFocus = NO;
                showingUpdateInBack = NO;
                activatingApp = NO;
            } else {
                driverShowingUpdateNow = YES;
                immediateFocus = appNearUpdaterInitialization;
                showingUpdateInBack = NO;
                activatingApp = appNearUpdaterInitialization;
            }
        }
        
        id <SPUStandardUserDriverDelegate> delegate = _delegate;
        BOOL handleShowingUpdates;
        if ([delegate respondsToSelector:@selector(standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:)]) {
            handleShowingUpdates = [delegate standardUserDriverShouldHandleShowingScheduledUpdate:(SUAppcastItem * _Nonnull)updateItem andInImmediateFocus:immediateFocus];
        } else {
            handleShowingUpdates = YES;
        }
        
        if (!handleShowingUpdates) {
            // Delay a runloop cycle to make sure the update can properly be checked
            __weak __typeof__(self) weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                __typeof__(self) strongSelf = weakSelf;
                if (strongSelf != nil) {
                    id<SPUStandardUserDriverDelegate> innerDelegate = strongSelf->_delegate;
                    if ([innerDelegate respondsToSelector:@selector(standardUserDriverWillHandleShowingUpdate:forUpdate:state:)]) {
                        [innerDelegate standardUserDriverWillHandleShowingUpdate:handleShowingUpdates forUpdate:(SUAppcastItem * _Nonnull)updateItem state:(SPUUserUpdateState * _Nonnull)state];
                    } else {
                        SULog(SULogLevelError, @"Error: Delegate <%@> is handling showing scheduled update but does not implement %@", innerDelegate, NSStringFromSelector(@selector(standardUserDriverWillHandleShowingUpdate:forUpdate:state:)));
                    }
                }
            });
        } else {
            // The update will be shown, but not necessarily immediately if !driverShowingUpdateNow
            // It is useful to post this early in case the delegate wants to post a notification
            if ([delegate respondsToSelector:@selector(standardUserDriverWillHandleShowingUpdate:forUpdate:state:)]) {
                [delegate standardUserDriverWillHandleShowingUpdate:handleShowingUpdates forUpdate:(SUAppcastItem * _Nonnull)updateItem state:(SPUUserUpdateState * _Nonnull)state];
            }
            
            if (!driverShowingUpdateNow) {
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
            } else {
                if (activatingApp) {
                    [self _activateApplication];
                }
                
                if (showingUpdateInBack) {
                    [_activeUpdateAlert.window orderBack:nil];
                } else {
                    [_activeUpdateAlert showWindow:nil];
                }
            }
        }
    }
}

- (void)_removeApplicationBecomeActiveObserver SPU_OBJC_DIRECT
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused aNotification
{
    [_activeUpdateAlert showWindow:nil];
    [_activeUpdateAlert setInstallButtonFocus:YES];
    
    [self _removeApplicationBecomeActiveObserver];
}

#pragma mark Update Found

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{
    assert(NSThread.isMainThread);
    
    [self closeCheckingWindow];
    
    if (_activeUpdateAlert != nil) {
        SULog(SULogLevelError, @"Error: -[%@ %@] should not be called when _activeUpdateAlert != nil:\n%@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), NSThread.callStackSymbols);
    }
    
    id<SPUStandardUserDriverDelegate> delegate = _delegate;
    id<SUVersionDisplay> customVersionDisplayer = nil;
    
    if ([delegate respondsToSelector:@selector(standardUserDriverRequestsVersionDisplayer)]) {
        customVersionDisplayer = [delegate standardUserDriverRequestsVersionDisplayer];
    }
    
    id<SUVersionDisplay> versionDisplayer = (customVersionDisplayer != nil) ? customVersionDisplayer : [SPUStandardVersionDisplay standardVersionDisplay];
    
    BOOL needsToObserveUserAttention = [delegate respondsToSelector:@selector(standardUserDriverDidReceiveUserAttentionForUpdate:)];
    
    __weak __typeof__(self) weakSelf = self;
    __weak id<SPUStandardUserDriverDelegate> weakDelegate = delegate;
    _activeUpdateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:appcastItem state:state host:_host versionDisplayer:versionDisplayer updaterSettings:_updaterSettings delegate:delegate completionBlock:^(SPUUserUpdateChoice choice, NSRect windowFrame, BOOL wasKeyWindow) {
        reply(choice);
        
        __typeof__(self) strongSelf = weakSelf;
        
        if (strongSelf != nil) {
            if (needsToObserveUserAttention && !strongSelf->_updateReceivedUserAttention) {
                strongSelf->_updateReceivedUserAttention = YES;
                
                id<SPUStandardUserDriverDelegate> strongDelegate = weakDelegate;
                // needsToObserveUserAttention already checks delegate responds to this selector
                [strongDelegate standardUserDriverDidReceiveUserAttentionForUpdate:appcastItem];
            }
            
            // Record the window frame of the update alert right before we deallocate it
            // So we can center future status window to where the update alert last was.
            // Also record if the window was inactive at the time a response was made
            // (the window may not be key if the window e.g. holds command while clicking on a response button)
            strongSelf->_updateAlertWindowFrameValue = [NSValue valueWithRect:windowFrame];
            strongSelf->_updateAlertWindowWasInactive = !wasKeyWindow;
            
            strongSelf->_activeUpdateAlert = nil;
        }
    } didBecomeKeyBlock:^{
        if (!needsToObserveUserAttention) {
            return;
        }
        
        if ([NSApp isActive]) {
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil && !strongSelf->_updateReceivedUserAttention) {
                strongSelf->_updateReceivedUserAttention = YES;
                
                id<SPUStandardUserDriverDelegate> strongDelegate = weakDelegate;
                // needsToObserveUserAttention already checks delegate responds to this selector
                [strongDelegate standardUserDriverDidReceiveUserAttentionForUpdate:appcastItem];
            }
        } else {
            // We need to listen for when the app becomes active again, and then test if the window alert
            // is still key. if it is, let the delegate know. Remove the observation after that.
            
            __typeof__(self) strongSelfOuter = weakSelf;
            if (strongSelfOuter != nil && strongSelfOuter->_applicationBecameActiveAfterUpdateAlertBecameKeyObserver == nil) {
                strongSelfOuter->_applicationBecameActiveAfterUpdateAlertBecameKeyObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidBecomeActiveNotification object:NSApp queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull __unused note) {
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil) {
                        if (!strongSelf->_updateReceivedUserAttention && [strongSelf->_activeUpdateAlert.window isKeyWindow]) {
                            strongSelf->_updateReceivedUserAttention = YES;
                            
                            id<SPUStandardUserDriverDelegate> strongDelegate = weakDelegate;
                            // needsToObserveUserAttention already checks delegate responds to this selector
                            [strongDelegate standardUserDriverDidReceiveUserAttentionForUpdate:appcastItem];
                        }
                        
                        if (strongSelf->_applicationBecameActiveAfterUpdateAlertBecameKeyObserver != nil) {
                            [[NSNotificationCenter defaultCenter] removeObserver:strongSelf->_applicationBecameActiveAfterUpdateAlertBecameKeyObserver];
                            
                            strongSelf->_applicationBecameActiveAfterUpdateAlertBecameKeyObserver = nil;
                        }
                    }
                }];
            }
        }
    }];
    
    _regularApplicationUpdate = [appcastItem.installationType isEqualToString:SPUInstallationTypeApplication];
    
    // For user initiated checks, let the delegate know we'll be showing an update
    // For scheduled checks, -setUpActiveUpdateAlertForUpdate:state: below will handle this
    if (state.userInitiated && [delegate respondsToSelector:@selector(standardUserDriverWillHandleShowingUpdate:forUpdate:state:)]) {
        [delegate standardUserDriverWillHandleShowingUpdate:YES forUpdate:appcastItem state:state];
    }
    
    [self setUpActiveUpdateAlertForScheduledUpdate:(state.userInitiated ? nil : appcastItem) state:state];
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    assert(NSThread.isMainThread);
    
    [_activeUpdateAlert showUpdateReleaseNotesWithDownloadData:downloadData];
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error
{
    assert(NSThread.isMainThread);
    
    // I don't want to expose SULog here because it's more of a user driver facing error
    // For our purposes we just ignore it and continue on..
    NSLog(@"Failed to download release notes with error: %@", error);
    [_activeUpdateAlert showReleaseNotesFailedToDownloadWithError:error];
}

- (void)showUpdateInFocus
{
    BOOL mayNeedToActivateApp;
    if (_activeUpdateAlert != nil) {
        [self setUpActiveUpdateAlertForScheduledUpdate:nil state:nil];
        mayNeedToActivateApp = NO;
    } else if (_permissionPrompt != nil) {
        [_permissionPrompt showWindow:nil];
        mayNeedToActivateApp = YES;
    } else if (_statusController != nil) {
        [_statusController showWindow:nil];
        mayNeedToActivateApp = YES;
    } else if (_checkingController != nil) {
        [_checkingController showWindow:nil];
        mayNeedToActivateApp = YES;
    } else if (_retryTerminatingApplication != nil) {
        [self _showAndConfigureStatusControllerForReadyToInstallWithAction:@selector(retryTermination:) closable:YES];
        mayNeedToActivateApp = YES;
    } else {
        mayNeedToActivateApp = NO;
    }
    
    if (mayNeedToActivateApp && ![NSApp isActive]) {
        // Make the app active if it's not already active, e.g, from a menu bar extra
        [self _activateApplication];
    }
}

#pragma mark Install & Relaunch Update

- (void)_showAndConfigureStatusControllerForReadyToInstallWithAction:(SEL)selector closable:(BOOL)closable SPU_OBJC_DIRECT
{
    [self createAndShowStatusControllerWithClosable:closable];
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    [_statusController beginActionWithTitle:SULocalizedStringFromTableInBundle(@"Ready to Install", SPARKLE_TABLE, sparkleBundle, nil) maxProgressValue:1.0 statusText:nil];
    [_statusController setProgressValue:1.0]; // Fill the bar.
    [_statusController setButtonEnabled:YES];
    [_statusController setButtonTitle:SULocalizedStringFromTableInBundle(@"Install and Relaunch", SPARKLE_TABLE, sparkleBundle, nil) target:self action:selector isDefault:YES accessibilityIdentifier:@"SUStatusInstallAndRelaunch"];
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))installUpdateHandler
{
    assert(NSThread.isMainThread);
    
    [self _showAndConfigureStatusControllerForReadyToInstallWithAction:@selector(installAndRestart:) closable:NO];
    
    [NSApp requestUserAttention:NSInformationalRequest];
    
    _installUpdateHandler = [installUpdateHandler copy];
}

- (void)installAndRestart:(id)__unused sender
{
    if (_installUpdateHandler != nil) {
        _installUpdateHandler(SPUUserUpdateChoiceInstall);
        _installUpdateHandler = nil;
    }
}

- (void)retryTermination:(id)__unused sender
{
    if (_retryTerminatingApplication != nil) {
        _retryTerminatingApplication();
    }
}

#pragma mark Check for Updates

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation
{
    assert(NSThread.isMainThread);
    
    _cancellation = [cancellation copy];
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    _checkingController = [[SUStatusController alloc] initWithHost:_host windowTitle:SULocalizedStringFromTableInBundle(@"Software Update", SPARKLE_TABLE, sparkleBundle, nil) centerPointValue:nil minimizable:NO closable:NO];
    [[_checkingController window] center]; // Force the checking controller to load its window.
    [_checkingController beginActionWithTitle:SULocalizedStringFromTableInBundle(@"Checking for updates…", SPARKLE_TABLE, sparkleBundle, nil) maxProgressValue:0.0 statusText:nil];
    [_checkingController setButtonTitle:SULocalizedStringFromTableInBundle(@"Cancel", SPARKLE_TABLE, sparkleBundle, nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO accessibilityIdentifier:@"SUStatusCancel"];
    
    // For background applications, obtain focus.
    // Useful if the update check is requested from another app like System Preferences.
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [self _activateApplication];
    }
    
    [_checkingController showWindow:self];
}

- (void)closeCheckingWindow SPU_OBJC_DIRECT
{
    if (_checkingController != nil)
    {
        [_checkingController close];
        _checkingController = nil;
        _cancellation = nil;
    }
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    if (_cancellation != nil) {
        _cancellation();
        _cancellation = nil;
    }
    [self closeCheckingWindow];
}

#pragma mark Update Errors

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    assert(NSThread.isMainThread);
    
    [self closeCheckingWindow];
    
    [_statusController close];
    _statusController = nil;
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    // Ideally we should use -[NSAlert alertWithError:] however
    // unfortunately Sparkle may return error messages with descriptions that contain
    // recovery suggestions. So we will check if an explicit recovery suggestion exists,
    // and set the mesage and informative text appropriately.
    // In the future we should audit potential error messages and make them consistent.
    NSAlert *alert = [[NSAlert alloc] init];
    NSString *recoverySuggestion = [error localizedRecoverySuggestion];
    if (recoverySuggestion != nil) {
        alert.messageText = error.localizedDescription;
        alert.informativeText = recoverySuggestion;
    } else {
        alert.messageText = SULocalizedStringFromTableInBundle(@"Update Error!", SPARKLE_TABLE, sparkleBundle, nil);
        alert.informativeText = error.localizedDescription;
    }
    
    [alert addButtonWithTitle:SULocalizedStringFromTableInBundle(@"Cancel Update", SPARKLE_TABLE, sparkleBundle, nil)];
    [self showAlert:alert secondaryAction:nil];
    
    acknowledgement();
}

- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    assert(NSThread.isMainThread);
    
    [self closeCheckingWindow];
    
    id <SPUStandardUserDriverDelegate> delegate = _delegate;
    
    id<SUVersionDisplay> customVersionDisplayer;
    if ([delegate respondsToSelector:@selector(standardUserDriverRequestsVersionDisplayer)]) {
        customVersionDisplayer = [delegate standardUserDriverRequestsVersionDisplayer];
    } else {
        customVersionDisplayer = nil;
    }
    
    SPUNoUpdateFoundReason reason = (SPUNoUpdateFoundReason)[(NSNumber *)error.userInfo[SPUNoUpdateFoundReasonKey] integerValue];
    
    SUAppcastItem *latestAppcastItem = error.userInfo[SPULatestAppcastItemFoundKey];
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#else
    NSBundle *sparkleBundle = nil;
#endif
    
    // If we have a custom version displayer, then override the recovery suggestion using the
    // proper version display
    NSError *presentationError;
    if (customVersionDisplayer != nil) {
        NSString *recoverySuggestion = SPUNoUpdateFoundRecoverySuggestion(reason, latestAppcastItem, _host, customVersionDisplayer, sparkleBundle);
        
        NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [error.userInfo mutableCopy];
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion;
        
        presentationError = [NSError errorWithDomain:error.domain code:error.code userInfo:[userInfo copy]];
    } else {
        presentationError = error;
    }
    
    NSAlert *alert = [NSAlert alertWithError:presentationError];
    alert.alertStyle = NSAlertStyleInformational;
    
    // Can we give more information to the user?
    void (^secondaryAction)(void) = nil;
    if (latestAppcastItem != nil) {
        switch (reason) {
            case SPUNoUpdateFoundReasonOnLatestVersion:
            case SPUNoUpdateFoundReasonOnNewerThanLatestVersion: {
                // Show the user the past version history if available

                // Check if the delegate allows showing the Version History
                BOOL shouldShowVersionHistory = (![delegate respondsToSelector:@selector(standardUserDriverShouldShowVersionHistoryForAppcastItem:)] || [delegate standardUserDriverShouldShowVersionHistoryForAppcastItem:latestAppcastItem]);
                
                if (shouldShowVersionHistory) {
                    NSString *localizedButtonTitle = SULocalizedStringFromTableInBundle(@"Version History", SPARKLE_TABLE, sparkleBundle, nil);
                    
                    // Check if the delegate implements its own Version History action
                    if ([delegate respondsToSelector:@selector(standardUserDriverShowVersionHistoryForAppcastItem:)]) {
                        [alert addButtonWithTitle:localizedButtonTitle];
                        
                        secondaryAction = ^{
                            [delegate standardUserDriverShowVersionHistoryForAppcastItem:latestAppcastItem];
                        };
                    } else if (latestAppcastItem.fullReleaseNotesURL != nil) {
                        // Open the full release notes URL if informed
                        [alert addButtonWithTitle:localizedButtonTitle];
                        
                        secondaryAction = ^{
                            [[NSWorkspace sharedWorkspace] openURL:(NSURL * _Nonnull)latestAppcastItem.fullReleaseNotesURL];
                        };
                    } else if (latestAppcastItem.releaseNotesURL != nil) {
                        // Fall back to opening the release notes URL
                        [alert addButtonWithTitle:localizedButtonTitle];
                        
                        secondaryAction = ^{
                            [[NSWorkspace sharedWorkspace] openURL:(NSURL * _Nonnull)latestAppcastItem.releaseNotesURL];
                        };
                    }
                }
                
                break;
            }
            case SPUNoUpdateFoundReasonSystemIsTooOld:
            case SPUNoUpdateFoundReasonSystemIsTooNew:
            case SPUNoUpdateFoundReasonHardwareDoesNotSupportARM64:
                if (latestAppcastItem.infoURL != nil) {
                    // Show the user the product's link if available
                    [alert addButtonWithTitle:SULocalizedStringFromTableInBundle(@"Learn More…", SPARKLE_TABLE, sparkleBundle, nil)];
                    
                    secondaryAction = ^{
                        [[NSWorkspace sharedWorkspace] openURL:(NSURL * _Nonnull)latestAppcastItem.infoURL];
                    };
                }
                break;
            case SPUNoUpdateFoundReasonUnknown:
                break;
        }
    }
    
    [self showAlert:alert secondaryAction:secondaryAction];
    
    acknowledgement();
}

- (void)showAlert:(NSAlert *)alert secondaryAction:(void (^ _Nullable)(void))secondaryAction SPU_OBJC_DIRECT
{
    id <SPUStandardUserDriverDelegate> delegate = _delegate;
    
    if ([delegate respondsToSelector:@selector(standardUserDriverWillShowModalAlert)]) {
        [delegate standardUserDriverWillShowModalAlert];
    }
    
    [alert setIcon:[SUApplicationInfo bestIconForHost:_host]];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn && secondaryAction != nil) {
        secondaryAction();
    }
    
    if ([delegate respondsToSelector:@selector(standardUserDriverDidShowModalAlert)]) {
        [delegate standardUserDriverDidShowModalAlert];
    }
}

#pragma mark Download & Install Updates

- (void)createAndShowStatusControllerWithClosable:(BOOL)closable SPU_OBJC_DIRECT
{
    if (_statusController == nil) {
        // We will make the status window minimizable for regular app updates which are often
        // quick and atomic to install on quit. But we won't do this for package based updates.
        id <SPUStandardUserDriverDelegate> delegate = _delegate;
        BOOL minimizable;
        if (!_regularApplicationUpdate) {
            minimizable = NO;
        } else if ([delegate respondsToSelector:@selector(standardUserDriverAllowsMinimizableStatusWindow)]) {
            minimizable = [delegate standardUserDriverAllowsMinimizableStatusWindow];
        } else {
            minimizable = YES;
        }
        
        NSValue *centerPointValue;
        if (_updateAlertWindowFrameValue != nil) {
            NSRect updateAlertFrame = _updateAlertWindowFrameValue.rectValue;
            NSPoint centerPoint = NSMakePoint(updateAlertFrame.origin.x + updateAlertFrame.size.width / 2.0, updateAlertFrame.origin.y + updateAlertFrame.size.height / 2.0);
            
            centerPointValue = [NSValue valueWithPoint:centerPoint];
        } else {
            centerPointValue = nil;
        }
        
        _statusController = [[SUStatusController alloc] initWithHost:_host windowTitle:[NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"Updating %@", SPARKLE_TABLE, SUSparkleBundle(), nil), _host.name] centerPointValue:centerPointValue minimizable:minimizable closable:closable];
        
        if (_updateAlertWindowWasInactive) {
            [_statusController.window orderFront:nil];
        } else {
            [_statusController showWindow:self];
        }
    }
}

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation
{
    assert(NSThread.isMainThread);
    
    _cancellation = [cancellation copy];
    
    [self createAndShowStatusControllerWithClosable:NO];
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    [_statusController beginActionWithTitle:SULocalizedStringFromTableInBundle(@"Downloading update…", SPARKLE_TABLE, sparkleBundle, @"Take care not to overflow the status window.") maxProgressValue:1.0 statusText:nil];
    [_statusController setProgressValue:0.0];
    [_statusController setButtonTitle:SULocalizedStringFromTableInBundle(@"Cancel", SPARKLE_TABLE, sparkleBundle, nil) target:self action:@selector(cancelDownload:) isDefault:NO accessibilityIdentifier:@"SUStatusCancel"];
    
    _bytesDownloaded = 0;
}

- (void)cancelDownload:(id)__unused sender
{
    if (_cancellation != nil) {
        _cancellation();
        _cancellation = nil;
    }
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    assert(NSThread.isMainThread);
    
    _expectedContentLength = expectedContentLength;
    if (expectedContentLength == 0) {
        [_statusController setMaxProgressValue:0.0];
    }
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    assert(NSThread.isMainThread);

    _bytesDownloaded += length;

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    [formatter setZeroPadsFractionDigits:YES];
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif

    if (_expectedContentLength > 0) {
        double newProgressValue = (double)_bytesDownloaded / (double)_expectedContentLength;
        
        [_statusController setProgressValue:MIN(newProgressValue, 1.0)];
        
        [_statusController setStatusText:[NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ of %@", SPARKLE_TABLE, sparkleBundle, @"The download progress in units of bytes, e.g. 100 KB of 1,0 MB"), [formatter stringFromByteCount:(long long)_bytesDownloaded], [formatter stringFromByteCount:(long long)MAX(_bytesDownloaded, _expectedContentLength)]]];
    } else {
        [_statusController setStatusText:[NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ downloaded", SPARKLE_TABLE, sparkleBundle, @"The download progress in a unit of bytes, e.g. 100 KB"), [formatter stringFromByteCount:(long long)_bytesDownloaded]]];
    }
}

- (void)showDownloadDidStartExtractingUpdate
{
    assert(NSThread.isMainThread);
    
    _cancellation = nil;
    
    [self createAndShowStatusControllerWithClosable:NO];
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    [_statusController beginActionWithTitle:SULocalizedStringFromTableInBundle(@"Extracting update…", SPARKLE_TABLE, sparkleBundle, @"Take care not to overflow the status window.") maxProgressValue:1.0 statusText:nil];
    [_statusController setProgressValue:0.0];
    [_statusController setButtonTitle:SULocalizedStringFromTableInBundle(@"Cancel", SPARKLE_TABLE, sparkleBundle, nil) target:nil action:nil isDefault:NO accessibilityIdentifier:@"SUStatusCancel"];
    [_statusController setButtonEnabled:NO];
}

- (void)showExtractionReceivedProgress:(double)progress
{
    assert(NSThread.isMainThread);
    
    [_statusController setProgressValue:progress];
}

- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated retryTerminatingApplication:(void (^)(void))retryTerminatingApplication
{
    assert(NSThread.isMainThread);
    
    if (applicationTerminated) {
        // Note this will only show up if -showReadyToInstallAndRelaunch: was called beforehand
        [_statusController beginActionWithTitle:SULocalizedStringFromTableInBundle(@"Installing update…", SPARKLE_TABLE, SUSparkleBundle(), @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [_statusController setButtonEnabled:NO];
    } else {
        // The "quit" event can always be canceled or delayed by the application we're updating
        // So we can't easily predict how long the installation will take or if it won't happen right away
        // We close our status window because we don't want it persisting for too long and have it obscure other windows
        [_statusController close];
        _statusController = nil;
        
        // Keep retry handler in case user tries to show update in focus again
        _retryTerminatingApplication = [retryTerminatingApplication copy];
    }
}

- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement
{
    assert(NSThread.isMainThread);
    
    // Close window showing update is installing
    [_statusController close];
    _statusController = nil;
    
    // Only show installed prompt when the app is not relaunched
    // When the app is relaunched, there is enough of a UI from relaunching the app.
    if (!relaunched) {
#if SPARKLE_COPY_LOCALIZATIONS
        NSBundle *sparkleBundle = SUSparkleBundle();
#endif
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = SULocalizedStringFromTableInBundle(@"Update Installed", SPARKLE_TABLE, sparkleBundle, nil);
        
        // Extract information from newly updated bundle if available
        NSString *hostName;
        NSString *hostVersion;
        NSBundle *newBundle = [NSBundle bundleWithURL:_oldHostBundleURL];
        if (newBundle != nil) {
            SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
            hostName = newHost.name;
            hostVersion = newHost.displayVersion;
        } else {
            // This may happen if Sparkle's normalization is enabled
            hostName = _oldHostName;
            hostVersion = nil;
        }
        
        if (hostVersion != nil) {
            alert.informativeText = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ is now updated to version %@!", SPARKLE_TABLE, sparkleBundle, nil), hostName, hostVersion];
        } else {
            alert.informativeText = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ is now updated!", SPARKLE_TABLE, sparkleBundle, nil), hostName];
        }
        [self showAlert:alert secondaryAction:nil];
    }
    
    acknowledgement();
}

#pragma mark Aborting Everything

- (void)dismissUpdateInstallation
{
    assert(NSThread.isMainThread);
    
    id<SPUStandardUserDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(standardUserDriverWillFinishUpdateSession)]) {
        [delegate standardUserDriverWillFinishUpdateSession];
    }
    
    if (_applicationBecameActiveAfterUpdateAlertBecameKeyObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_applicationBecameActiveAfterUpdateAlertBecameKeyObserver];
        _applicationBecameActiveAfterUpdateAlertBecameKeyObserver = nil;
    }
    
    _updateReceivedUserAttention = NO;
    _installUpdateHandler = nil;
    _cancellation = nil;
    _retryTerminatingApplication = nil;
    
    [self closeCheckingWindow];
    
    if (_permissionPrompt) {
        [_permissionPrompt close];
        _permissionPrompt = nil;
    }
    
    if (_statusController) {
        [_statusController close];
        _statusController = nil;
    }
    
    if (_activeUpdateAlert) {
        [_activeUpdateAlert close];
        _activeUpdateAlert = nil;
    }
    
    [self _removeApplicationBecomeActiveObserver];
}

@end

#endif
