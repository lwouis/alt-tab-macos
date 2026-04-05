//
//  SPUInstallerDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallerDriver.h"
#import "SULog.h"
#import "SPUMessageTypes.h"
#import "SPUXPCServiceInfo.h"
#import "SPUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SUAppcastItem+Private.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUHost.h"
#import "SUFileManager.h"
#import "SPUSecureCoding.h"
#import "SPUInstallationInputData.h"
#import "SUInstallerLauncher.h"
#import "SUInstallerConnection.h"
#import "SUInstallerConnectionProtocol.h"
#import "SUXPCInstallerConnection.h"
#import "SPUDownloadedUpdate.h"
#import "SPUInstallationType.h"
#import "SUConstants.h"
#import "SPUProbeInstallStatus.h"


#include "AppKitPrevention.h"

#define FIRST_INSTALLER_MESSAGE_TIMEOUT 7ull

#if SPARKLE_BUILD_LEGACY_SUUPDATER
@interface NSObject (PrivateDelegateMethods)

- (nullable NSString *)_pathToRelaunchForUpdater:(SPUUpdater *)updater;

@end
#endif

// Note: we don't want to directly pull in AppKit here especially if the main application does not need it
@interface NSObject (ActivationAPIs)
// NSApplication
+ (id)sharedApplication;
- (void)yieldActivationToApplication:(id)application;

// NSRunningApplication
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)bundleIdentifier;
- (NSURL *)bundleURL;
@end

@interface SPUInstallerDriver () <SUInstallerCommunicationProtocol>
@end

@implementation SPUInstallerDriver
{
    SUHost *_host;
    NSBundle *_applicationBundle;
    id<SUInstallerConnectionProtocol> _installerConnection;
    SUAppcastItem *_updateItem;
    NSData *_updateURLBookmarkData;
    NSError *_installerError;
    
    __weak id _updater;
    __weak id<SPUUpdaterDelegate> _updaterDelegate;
    __weak id<SPUInstallerDriverDelegate> _delegate;
    
    void (^_updateWillInstallHandler)(void);
    
    SPUInstallerMessageType _currentStage;
    NSUInteger _extractionAttempts;
    
    BOOL _postponedOnce;
    BOOL _relaunch;
    BOOL _systemDomain;
    BOOL _aborted;
    BOOL _notifiedDelegateInstallationWillFinish;
}

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater updaterDelegate:(id<SPUUpdaterDelegate>)updaterDelegate delegate:(nullable id<SPUInstallerDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _applicationBundle = applicationBundle;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _delegate = delegate;
    }
    return self;
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
    _updateWillInstallHandler = [updateWillInstallHandler copy];
}

- (void)_reportInstallerError:(nullable NSError *)currentInstallerError genericErrorCode:(NSInteger)genericErrorCode genericUserInfo:(NSDictionary *)genericUserInfo SPU_OBJC_DIRECT
{
    // First see if there is a good custom error we can show
    // We only check for signing validation errors and installation errors due to not having write permission currently
    NSError *customError = nil;
    if (currentInstallerError != nil) {
        NSError *underlyingError = currentInstallerError.userInfo[NSUnderlyingErrorKey];
        if (underlyingError != nil) {
            if (underlyingError.code == SUValidationError) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: SULocalizedStringFromTableInBundle(@"The update is improperly signed and could not be validated. Please try again later or contact the app developer.", SPARKLE_TABLE, SUSparkleBundle(), nil),
                    NSUnderlyingErrorKey: (NSError * _Nonnull)currentInstallerError
                };
                
                customError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
            } else if (underlyingError.code == SUInstallationError) {
                NSError *secondUnderlyingError = underlyingError.userInfo[NSUnderlyingErrorKey];
                if (secondUnderlyingError != nil && [secondUnderlyingError.domain isEqualToString:NSCocoaErrorDomain] && secondUnderlyingError.code == NSFileWriteNoPermissionError) {
                    // Note: these error strings will only surface for external app updaters like sparkle-cli (i.e, updaters that update other app bundles)
                    
#if SPARKLE_COPY_LOCALIZATIONS
                    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
                    
                    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                        NSLocalizedDescriptionKey: SULocalizedStringFromTableInBundle(@"The installation failed due to not having permission to write the new update.", SPARKLE_TABLE, sparkleBundle, nil),
                        NSUnderlyingErrorKey: (NSError * _Nonnull)currentInstallerError
                    }];
                    
                    // macOS 13 and later introduce a policy where Gatekeeper can block app modifications if the apps have different Team IDs
                    if (@available(macOS 13, *)) {
                        NSBundle *mainBundle = [NSBundle mainBundle];
                        if (![mainBundle isEqual:_host.bundle]) {
                            SUHost *mainBundleHost = [[SUHost alloc] initWithBundle:mainBundle];
                            
                            userInfo[NSLocalizedRecoverySuggestionErrorKey] = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"You may need to allow modifications from %1$@ in System Settings under Privacy & Security and App Management to install future updates.", SPARKLE_TABLE, sparkleBundle, nil), mainBundleHost.name];
                        }
                    }
                    
                    customError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationWriteNoPermissionError userInfo:userInfo];
                }
            }
        }
    }
    
    // Otherwise if there's no custom error, then use a generic installer error to show
    // and keep the underlying error around for logging
    NSError *installerError;
    if (customError != nil) {
        installerError = customError;
    } else {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:genericUserInfo];
        if (currentInstallerError != nil) {
            userInfo[NSUnderlyingErrorKey] = currentInstallerError;
        }
        installerError = [NSError errorWithDomain:SUSparkleErrorDomain code:genericErrorCode userInfo:userInfo];
    }
    
    [_delegate installerIsRequestingAbortInstallWithError:installerError];
}

- (void)setUpConnection SPU_OBJC_DIRECT
{
    if (_installerConnection != nil) {
        return;
    }
    
    NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    BOOL usingInstallerService;
#if INSTALLER_CONNECTION_XPC_SERVICE_EMBEDDED
    if (SPUXPCServiceIsEnabled(SUEnableInstallerConnectionServiceKey)) {
        _installerConnection = [[SUXPCInstallerConnection alloc] initWithDelegate:self];
        usingInstallerService = YES;
    } else
#endif
    {
        _installerConnection = [[SUInstallerConnection alloc] initWithDelegate:self remote:NO];
        usingInstallerService = NO;
    }
    
    __weak __typeof__(self) weakSelf = self;
    [_installerConnection setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf->_installerConnection != nil && !strongSelf->_aborted) {
                NSString *impactedTools = usingInstallerService ? (@SPARKLE_RELAUNCH_TOOL_NAME" and "@INSTALLER_LAUNCHER_NAME) : @SPARKLE_RELAUNCH_TOOL_NAME;
                
                NSString *additionalFailureReason;
                {
                    NSString *executableFailureReason;
                    if (!SPUHelperHasExecutablePermission(@SPARKLE_RELAUNCH_TOOL_NAME, &executableFailureReason) || !SPUHelperHasExecutablePermission(@SPARKLE_INSTALLER_PROGRESS_TOOL_NAME@".app/Contents/MacOS/"@SPARKLE_INSTALLER_PROGRESS_TOOL_NAME, &executableFailureReason)) {
                        additionalFailureReason = executableFailureReason;
                    } else {
                        additionalFailureReason = [NSString stringWithFormat:@"If your application is sandboxed, please ensure Installer Connection & Status entitlements are correctly set up: https://sparkle-project.org/documentation/sandboxing/ . Otherwise if %@ %@ not adhoc signed, your app must be signed with a matching team ID", impactedTools, (usingInstallerService ? @"are" : @"is")];
                    }
                }
                
                NSDictionary *genericUserInfo = @{
                    NSLocalizedDescriptionKey: SULocalizedStringFromTableInBundle(@"An error occurred while running the updater. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil),
                    NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"The remote port connection was invalidated from the updater. %@. For additional details, check Console logs for %@", additionalFailureReason, impactedTools]
                };
                
                [strongSelf _reportInstallerError:strongSelf->_installerError genericErrorCode:SUInstallationError genericUserInfo:genericUserInfo];
            }
        });
    }];
    
    NSString *serviceName = SPUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier);
    NSString *installationType = _updateItem.installationType;
    assert(installationType != nil);
    
    [_installerConnection setServiceName:serviceName systemDomain:_systemDomain];
}

// This can be called multiple times (eg: if a delta update fails, this may be called again with a regular update item)
- (void)extractDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate silently:(BOOL)silently completion:(void (^)(NSError * _Nullable))completionHandler
{
    _updateItem = downloadedUpdate.updateItem;
    _updateURLBookmarkData = downloadedUpdate.downloadBookmarkData;
    
    _currentStage = SPUInstallerNotStarted;
    
    if (_installerConnection == nil) {
        [self launchAutoUpdateSilently:silently completion:completionHandler];
    } else {
        // The Install tool is already alive; just send out installation input data again
        [self sendInstallationData];
        completionHandler(nil);
    }
}

- (void)resumeInstallingUpdateWithUpdateItem:(SUAppcastItem *)updateItem systemDomain:(BOOL)systemDomain
{
    _updateItem = updateItem;
    _systemDomain = systemDomain;
}

- (void)sendInstallationData SPU_OBJC_DIRECT
{
    NSString *pathToRelaunch = _applicationBundle.bundlePath;
    
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    id updater = _updater;
    
#if SPARKLE_BUILD_LEGACY_SUUPDATER
    // Give the delegate one more chance for determining the path to relaunch via a private API used by SUUpdater
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(_pathToRelaunchForUpdater:)]) {
        NSString *relaunchPath = [(NSObject *)updaterDelegate _pathToRelaunchForUpdater:updater];
        if (relaunchPath != nil) {
            pathToRelaunch = relaunchPath;
        }
    }
#endif

    NSString *decryptionPassword = nil;
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(decryptionPasswordForUpdater:)]) {
        decryptionPassword = [updaterDelegate decryptionPasswordForUpdater:updater];
    }
    
    id<SPUInstallerDriverDelegate> delegate = _delegate;
    
    SPUInstallationInputData *installationData = [[SPUInstallationInputData alloc] initWithRelaunchPath:pathToRelaunch hostBundlePath:_host.bundlePath updateURLBookmarkData:_updateURLBookmarkData installationType:_updateItem.installationType signatures:_updateItem.signatures decryptionPassword:decryptionPassword expectedVersion:_updateItem.versionString expectedContentLength:_updateItem.contentLength];
    
    NSData *archivedData = SPUArchiveRootObjectSecurely(installationData);
    if (archivedData == nil) {
        [delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:@"An error occurred while encoding the installer parameters. Please try again later." }]];
        return;
    }
    
    [_installerConnection handleMessageWithIdentifier:SPUInstallationData data:archivedData];
    
    _currentStage = SPUInstallerNotStarted;
    
    // If the number of extractions attempts stays the same, then we've waited too long and should abort the installation
    // The extraction attempts is incremented when we receive an extraction should start message from the installer
    // This also handles the case when a delta extraction fails and tries to re-try another extraction attempt later
    // We will also want to make sure current stage is still SUInstallerNotStarted because it may not be due to resumability
    NSUInteger currentExtractionAttempts = _extractionAttempts;
    __weak __typeof__(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FIRST_INSTALLER_MESSAGE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_currentStage == SPUInstallerNotStarted && currentExtractionAttempts == strongSelf->_extractionAttempts) {
            SULog(SULogLevelError, @"Timeout: Installer never started archive extraction");
            [strongSelf->_delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred while starting the installer. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil) }]];
        }
    });
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _handleMessageWithIdentifier:identifier data:data];
    });
}

- (void)_handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data SPU_OBJC_DIRECT
{
    if (!SPUInstallerMessageTypeIsLegal(_currentStage, (SPUInstallerMessageType)identifier)) {
        SULog(SULogLevelError, @"Error: received out of order message with current stage: %d, requested stage: %d", _currentStage, identifier);
        return;
    }
    
    id<SPUInstallerDriverDelegate> delegate = _delegate;
    
    if (identifier == SPUExtractionStarted) {
        _extractionAttempts++;
        _currentStage = (SPUInstallerMessageType)identifier;
        [delegate installerDidStartExtracting];
    } else if (identifier == SPUExtractedArchiveWithProgress) {
        if (data.length == sizeof(double) && sizeof(double) == sizeof(uint64_t)) {
            uint64_t progressValue = CFSwapInt64LittleToHost(*(const uint64_t *)data.bytes);
            double progress = *(double *)&progressValue;
            [delegate installerDidExtractUpdateWithProgress:progress];
            _currentStage = (SPUInstallerMessageType)identifier;
        }
    } else if (identifier == SPUArchiveExtractionFailed) {
        // If this is a delta update, there must be a regular update we can fall back to
        if ([_updateItem isDeltaUpdate]) {
            [delegate installerDidFailToApplyDeltaUpdate];
        } else {
            // Don't have to store current stage because we're going to abort
            NSDictionary *genericUserInfo = @{ NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred while extracting the archive. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil) };
            
            NSError *unarchivedError = (NSError *)SPUUnarchiveRootObjectSecurely(data, [NSError class]);
            [self _reportInstallerError:unarchivedError genericErrorCode:SUUnarchivingError genericUserInfo:genericUserInfo];
        }
    } else if (identifier == SPUValidationStarted) {
        _currentStage = (SPUInstallerMessageType)identifier;
    } else if (identifier == SPUInstallationStartedStage1) {
        _currentStage = (SPUInstallerMessageType)identifier;
    } else if (identifier == SPUInstallationFinishedStage1) {
        _currentStage = (SPUInstallerMessageType)identifier;
        
        // Let the installer keep a copy of the appcast item data
        // We may want to ask for it later (note the updater can relaunch without the app necessarily having relaunched)
        NSData *updateItemData = SPUArchiveRootObjectSecurely(_updateItem);
        
        if (updateItemData != nil) {
            [_installerConnection handleMessageWithIdentifier:SPUSentUpdateAppcastItemData data:updateItemData];
        } else {
            SULog(SULogLevelError, @"Error: Archived data to send for appcast item is nil");
        }
        
        BOOL hasTargetTerminated = NO;
        if (data.length >= sizeof(uint8_t)) {
            hasTargetTerminated = (BOOL)*((const uint8_t *)data.bytes);
        }
        
        [delegate installerDidFinishPreparationAndWillInstallImmediately:hasTargetTerminated];
    } else if (identifier == SPUInstallationFinishedStage2) {
        _currentStage = (SPUInstallerMessageType)identifier;
        
        BOOL hasTargetTerminated = NO;
        if (data.length >= sizeof(uint8_t)) {
            hasTargetTerminated = (BOOL)*((const uint8_t *)data.bytes);
        }
        
        // If the target was already terminated this may be the first time we notify delegate that installation is about to happen
        // Otherwise if the target was requested to be terminated/relaunched by the user this may be the second time
        // Avoid re-notifying the delegate twice
        if (!_notifiedDelegateInstallationWillFinish) {
            _notifiedDelegateInstallationWillFinish = YES;
            [delegate installerWillFinishInstallationAndRelaunch:_relaunch];
        }
        
        [delegate installerDidStartInstallingWithApplicationTerminated:hasTargetTerminated];
    } else if (identifier == SPUInstallationFinishedStage3) {
        _currentStage = (SPUInstallerMessageType)identifier;
        
        [_installerConnection invalidate];
        _installerConnection = nil;
        
        [delegate installerDidFinishInstallationAndRelaunched:_relaunch acknowledgement:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate installerIsRequestingAbortInstallWithError:nil];
            });
        }];
    } else if (identifier == SPUUpdaterAlivePing) {
        // Don't update the current stage; a ping request has no effect on that.
        [_installerConnection handleMessageWithIdentifier:SPUUpdaterAlivePong data:[NSData data]];
    } else if (identifier == SPUInstallerError) {
        // Don't update the current stage; an installation error has no effect on that.
        _installerError = (NSError *)SPUUnarchiveRootObjectSecurely(data, [NSError class]);
    }
}

- (void)launchAutoUpdateSilently:(BOOL)silently completion:(void (^)(NSError *_Nullable))completionHandler SPU_OBJC_DIRECT
{
    id<SUInstallerLauncherProtocol> installerLauncher;
    
#if INSTALLER_LAUNCHER_XPC_SERVICE_EMBEDDED
    __block BOOL retrievedLaunchStatus = NO;
    NSXPCConnection *launcherConnection = nil;
    
    if (SPUXPCServiceIsEnabled(SUEnableInstallerLauncherServiceKey)) {
        launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_LAUNCHER_BUNDLE_ID];
        launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
        
        launcherConnection.interruptionHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedLaunchStatus) {
                    // We'll break the retain cycle in the invalidation handler
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    [launcherConnection invalidate];
#pragma clang diagnostic pop
                }
            });
        };
        
        launcherConnection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
                if (!retrievedLaunchStatus) {
#pragma clang diagnostic pop
                    NSString *additionalFailureReason;
                    {
                        NSString *executableFailureReason;
                        if (!SPUXPCServiceHasExecutablePermission(@INSTALLER_LAUNCHER_NAME, &executableFailureReason)) {
                            additionalFailureReason = [NSString stringWithFormat:@" %@", executableFailureReason];
                        } else {
                            additionalFailureReason = @"";
                        }
                    }
                    
                    NSError *error =
                    [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred while connecting to the installer. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil),
                        NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"If your app is not sandboxed, please remove or disable %@ in your app's Info.plist. Please also check Console logs for "@INSTALLER_LAUNCHER_NAME" and "@SPARKLE_RELAUNCH_TOOL_NAME" processes if there are additional details.%@", SUEnableInstallerLauncherServiceKey, additionalFailureReason]}];
                    
                    completionHandler(error);
                    
                    // Break the retain cycle
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    launcherConnection.interruptionHandler = nil;
                    launcherConnection.invalidationHandler = nil;
#pragma clang diagnostic pop
                }
            });
        };
        
        [launcherConnection resume];
        
        installerLauncher = launcherConnection.remoteObjectProxy;
    } else
#endif
    {
        installerLauncher = [[SUInstallerLauncher alloc] init];
    }
    
    // Our driver (automatic or UI based) has a say if interaction is allowed as well
    // An automatic driver may disallow interaction but the updater could try again later for a UI based driver that does allow interaction
    BOOL driverAllowsInteraction = !silently;
    
    NSString *hostBundlePath = _host.bundle.bundlePath;
    assert(hostBundlePath != nil);
    
    NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
    
    NSString *installationType = _updateItem.installationType;
    assert(installationType != nil);
    
    [installerLauncher launchInstallerWithHostBundlePath:hostBundlePath mainBundlePath:NSBundle.mainBundle.bundlePath installationType:installationType allowingDriverInteraction:driverAllowsInteraction completion:^(SUInstallerLauncherStatus result, BOOL systemDomain) {
        dispatch_async(dispatch_get_main_queue(), ^{
#if INSTALLER_LAUNCHER_XPC_SERVICE_EMBEDDED
            retrievedLaunchStatus = YES;
            [launcherConnection invalidate];
#endif
            
            switch (result) {
                case SUInstallerLauncherFailure:
                    SULog(SULogLevelError, @"Error: Failed to gain authorization required to update target");
                    completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred while launching the installer. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil) }]);
                    break;
                case SUInstallerLauncherCanceled:
                    completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationCanceledError userInfo:nil]);
                    break;
                case SUInstallerLauncherAuthorizeLater:
                    completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationAuthorizeLaterError userInfo:nil]);
                    break;
                case SUInstallerLauncherSuccess:
                    self->_systemDomain = systemDomain;
                    [self setUpConnection];
                    [self sendInstallationData];

                    // Complete immediately so the caller can set up state (e.g., _downloadedUpdateForRemoval)
                    // before installer messages arrive on the main queue.
                    // Previously, completionHandler was called inside the probe callback, which meant
                    // installer messages (SPUExtractionStarted, SPUArchiveExtractionFailed) could be
                    // processed before the completion handler fired, leaving _downloadedUpdateForRemoval
                    // unset and causing an assertion crash in clearDownloadedUpdate.
                    completionHandler(nil);

                    // Send a probe/ping to the status service, which should boost/prioritize its startup
                    if (hostBundleIdentifier != nil) {
                        [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:hostBundleIdentifier completion:^(BOOL stausServiceIsRunning) {
                            if (!stausServiceIsRunning) {
                                SULog(SULogLevelError, @"Error: failed to probe status service for %@ from the framework", hostBundleIdentifier);
                            }
                        }];
                    }
                    
                    break;
            }
        });
    }];
}

- (BOOL)mayUpdateAndRestart SPU_OBJC_DIRECT
{
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    return (!updaterDelegate || ![updaterDelegate respondsToSelector:@selector((updaterShouldRelaunchApplication:))] || [updaterDelegate updaterShouldRelaunchApplication:_updater]);
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(_updateItem);
    
    id<SPUInstallerDriverDelegate> delegate = _delegate;
    
    if (![self mayUpdateAndRestart])
    {
        [delegate installerIsRequestingAbortInstallWithError:nil];
        return;
    }
    
    // Give the host app an opportunity to postpone the install and relaunch.
    if (!_postponedOnce)
    {
        id updater = _updater;
        id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)]) {
            _postponedOnce = YES;
            __weak __typeof__(self) weakSelf = self;
            if ([updaterDelegate updater:updater shouldPostponeRelaunchForUpdate:_updateItem untilInvokingBlock:^{
                [weakSelf installWithToolAndRelaunch:relaunch displayingUserInterface:showUI];
            }]) {
                return;
            }
        }
    }
    
    if (_updateWillInstallHandler != NULL) {
        _updateWillInstallHandler();
    }
    
    // Set up connection to the installer if one is not set up already
    [self setUpConnection];
    
    // For resumability, we'll assume we are far enough for the installation to continue
    _currentStage = SPUInstallationFinishedStage1;
    
    _relaunch = relaunch;
    
    // If AppKit is loaded, we will yield to our Sparkle progress app
    // This will let the system know it should be okay for the progress agent to activate itself (if necessary)
    // Note we don't want to directly pull in AppKit here especially if the main application does not need it
    if (showUI) {
        if (@available(macOS 14, *)) {
            // Make sure we are not root before using AppKit API
            if (geteuid() != 0) {
                Class applicationClass = NSClassFromString(@"NSApplication");
                if ([applicationClass respondsToSelector:@selector(sharedApplication)]) {
                    NSObject *application = [applicationClass sharedApplication];
                    
                    if ([application respondsToSelector:@selector(yieldActivationToApplication:)]) {
                        Class runningApplicationClass = NSClassFromString(@"NSRunningApplication");
                        if ([runningApplicationClass respondsToSelector:@selector(runningApplicationsWithBundleIdentifier:)]) {
                            NSArray *runningApplications = [runningApplicationClass runningApplicationsWithBundleIdentifier:@SPARKLE_INSTALLER_PROGRESS_TOOL_BUNDLE_ID];
                            
                            NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
                            
                            id targetRunningApplication = nil;
                            for (id runningApplication in runningApplications) {
                                if ([(NSObject *)runningApplication respondsToSelector:@selector(bundleURL)]) {
                                    NSURL *bundleURL = [(NSObject *)runningApplication bundleURL];
                                    
                                    if (hostBundleIdentifier != nil && [bundleURL.pathComponents containsObject:hostBundleIdentifier]) {
                                        targetRunningApplication = runningApplication;
                                        break;
                                    }
                                }
                            }
                            
                            if (targetRunningApplication != nil) {
                                [application yieldActivationToApplication:targetRunningApplication];
                            }
                        }
                    }
                }
            }
        }
    }
    
    // The user can request trying to relaunch/quit the app multiple times
    // Avoid re-notifying the delegate twice
    if (!_notifiedDelegateInstallationWillFinish) {
        _notifiedDelegateInstallationWillFinish = YES;
        [delegate installerWillFinishInstallationAndRelaunch:relaunch];
    }
    
    uint8_t response[2] = {(uint8_t)relaunch, (uint8_t)showUI};
    NSData *responseData = [NSData dataWithBytes:response length:sizeof(response)];
    
    // the installer will send us SPUInstallationFinishedStage2 when stage 2 is done
    [_installerConnection handleMessageWithIdentifier:SPUResumeInstallationToStage2 data:responseData];
}

- (void)cancelUpdate
{
    // Set up connection to the installer if one is not set up already
    [self setUpConnection];
    
    _aborted = YES;
    
    [_installerConnection handleMessageWithIdentifier:SPUCancelInstallation data:[NSData data]];
    
    [_delegate installerIsRequestingAbortInstallWithError:nil];
}

- (void)abortInstall
{
    _aborted = YES;
    if (_installerConnection != nil) {
        [_installerConnection invalidate];
        _installerConnection = nil;
    }
}

@end
