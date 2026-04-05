//
//  SPUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUAutomaticUpdateDriver.h"
#import "SPUUpdateDriver.h"
#import "SUHost.h"
#import "SPUUpdaterDelegate.h"
#import "SPUCoreBasedUpdateDriver.h"
#import "SULog.h"
#import "SUAppcastItem.h"
#import "SPUUserDriver.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface SPUAutomaticUpdateDriver () <SPUCoreBasedUpdateDriverDelegate>
@end

@implementation SPUAutomaticUpdateDriver
{
    SPUCoreBasedUpdateDriver *_coreDriver;
    SUAppcastItem* _updateItem;
    
    __weak id _updater;
    __weak id<SPUUserDriver> _userDriver;
    __weak id _updaterDelegate;
    
    BOOL _installerDidFinishPreparation;
}

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _updater = updater;
        // The user driver is only used for a termination callback
        _userDriver = userDriver;
        _updaterDelegate = updaterDelegate;
        _coreDriver = [[SPUCoreBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle updateCheck:SPUUpdateCheckUpdatesInBackground updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [_coreDriver setCompletionHandler:completionBlock];
}

- (void)setUpdateShownHandler:(void (^)(void))updateShownHandler
{
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
    [_coreDriver setUpdateWillInstallHandler:updateWillInstallHandler];
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders
{
    [_coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES requiresSilentInstall:YES];
}

- (void)resumeInstallingUpdate
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(SULogLevelError, @"Error: resumeInstallingUpdate: called on SPUAutomaticUpdateDriver");
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)__unused resumableUpdate
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(SULogLevelError, @"Error: resumeDownloadedUpdate: called on SPUAutomaticUpdateDriver");
}

// Note: critical updates can be downloaded automatically first before needing user attention
static BOOL SPUUpdateRequiresUserAttentionBeforeDownloading(SUAppcastItem *updateItem)
{
    return (updateItem.isInformationOnlyUpdate || updateItem.majorUpgrade || updateItem.signingValidationStatus == SPUAppcastSigningValidationStatusFailed);
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem
{
    _updateItem = updateItem;
    
    if (SPUUpdateRequiresUserAttentionBeforeDownloading(updateItem)) {
        [_coreDriver deferInformationalUpdate:updateItem secondaryUpdate:secondaryUpdateItem];
        [self abortUpdate];
    } else {
        [_coreDriver downloadUpdateFromAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem inBackground:YES];
    }
}

- (BOOL)showingUpdate
{
    return NO;
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately
{
    _installerDidFinishPreparation = YES;
    
    if (!willInstallImmediately) {
        BOOL installationHandledByDelegate = NO;
        id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)]) {
            __weak __typeof__(self) weakSelf = self;
            installationHandledByDelegate = [updaterDelegate updater:_updater willInstallUpdateOnQuit:_updateItem immediateInstallationBlock:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil) {
                        [strongSelf->_coreDriver finishInstallationWithResponse:SPUUserUpdateChoiceInstall displayingUserInterface:NO];
                    }
                });
            }];
        }
        
        if (!installationHandledByDelegate) {
            // We are done and can safely abort now
            // The installer tool will keep the installation alive
            [self abortUpdate];
        }
    }
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(NSError *)error
{
    // It should not be necessary to include properties from SPUUpdateRequiresUserAttentionBeforeDownloading() because _installerDidFinishPreparation should be NO in those cases,
    // but we'll include the check anyway
    BOOL showNextUpdateImmediately = (error == nil || error.code == SUInstallationAuthorizeLaterError) && (!_installerDidFinishPreparation || _updateItem.criticalUpdate || SPUUpdateRequiresUserAttentionBeforeDownloading(_updateItem));
    
    [_coreDriver abortUpdateAndShowNextUpdateImmediately:showNextUpdateImmediately error:error];
}

@end
