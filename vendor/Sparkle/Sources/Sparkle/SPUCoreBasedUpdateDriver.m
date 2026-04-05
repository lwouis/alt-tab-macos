//
//  SPUCoreBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUCoreBasedUpdateDriver.h"
#import "SUHost.h"
#import "SPUUpdaterDelegate.h"
#import "SPUBasicUpdateDriver.h"
#import "SPUInstallerDriver.h"
#import "SPUDownloadDriver.h"
#import "SULog.h"
#import "SULog+NSError.h"
#import "SUErrors.h"
#import "SPUResumableUpdate.h"
#import "SPUDownloadedUpdate.h"
#import "SPUInformationalUpdate.h"
#import "SUAppcastItem.h"
#import "SULocalizations.h"
#import "SPUInstallationType.h"
#import "SUPhasedUpdateGroupInfo.h"


#include "AppKitPrevention.h"

@interface SPUCoreBasedUpdateDriver () <SPUBasicUpdateDriverDelegate, SPUDownloadDriverDelegate, SPUInstallerDriverDelegate>
@end

@implementation SPUCoreBasedUpdateDriver
{
    SPUBasicUpdateDriver *_basicDriver;
    SPUDownloadDriver *_downloadDriver;
    SPUInstallerDriver *_installerDriver;
    SUAppcastItem *_updateItem;
    SUAppcastItem * _Nullable _secondaryUpdateItem;
    id<SPUResumableUpdate> _resumableUpdate;
    SPUDownloadedUpdate *_downloadedUpdateForRemoval;
    SUHost *_host;
    NSString *_userAgent;
    NSDictionary * _Nullable _httpHeaders;
    
    __weak id _updater; // if we didn't have legacy support, I'd remove this..
    __weak id <SPUUpdaterDelegate> _updaterDelegate;
    __weak id<SPUCoreBasedUpdateDriverDelegate> _delegate;
    
    BOOL _resumingInstallingUpdate;
    BOOL _silentInstall;
}

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updateCheck:(SPUUpdateCheck)updateCheck updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUCoreBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        
        NSString *bundleIdentifier = host.bundle.bundleIdentifier;
        assert(bundleIdentifier != nil);
        
        _basicDriver = [[SPUBasicUpdateDriver alloc] initWithHost:host updateCheck:updateCheck updater:updater updaterDelegate:updaterDelegate delegate:self];
        _installerDriver = [[SPUInstallerDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
        
        _host = host;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [_basicDriver setCompletionHandler:completionBlock];
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
    [_installerDriver setUpdateWillInstallHandler:updateWillInstallHandler];
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background requiresSilentInstall:(BOOL)silentInstall
{
    _userAgent = [userAgent copy];
    _httpHeaders = httpHeaders;
    _silentInstall = silentInstall;
    
    [_basicDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:background];
}

- (void)resumeInstallingUpdate
{
    _resumingInstallingUpdate = YES;
    _silentInstall = NO;
    
    [_basicDriver resumeInstallingUpdate];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
    _resumableUpdate = resumableUpdate;
    _silentInstall = NO;
    
    [_basicDriver resumeUpdate:resumableUpdate];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain
{
    _updateItem = updateItem;
    _secondaryUpdateItem = secondaryUpdateItem;
    
    if (_resumingInstallingUpdate) {
        assert(systemDomain != nil);
        [_installerDriver resumeInstallingUpdateWithUpdateItem:updateItem systemDomain:systemDomain.boolValue];
    }
    
    [_delegate basicDriverDidFindUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem];
}

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem inBackground:(BOOL)background SPU_OBJC_DIRECT
{
    _downloadDriver = [[SPUDownloadDriver alloc] initWithUpdateItem:updateItem secondaryUpdateItem:secondaryUpdateItem host:_host userAgent:_userAgent httpHeaders:_httpHeaders inBackground:background delegate:self];
    
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil && [updaterDelegate respondsToSelector:@selector((updater:willDownloadUpdate:withRequest:))]) {
        [updaterDelegate updater:updater willDownloadUpdate:updateItem withRequest:_downloadDriver.request];
    }
    
    [_downloadDriver downloadFile];
}

- (void)downloadDriverWillBeginDownload
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(downloadDriverWillBeginDownload)]) {
        [delegate downloadDriverWillBeginDownload];
    }
}

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(downloadDriverDidReceiveExpectedContentLength:)]) {
        [delegate downloadDriverDidReceiveExpectedContentLength:expectedContentLength];
    }
}

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(downloadDriverDidReceiveDataOfLength:)]) {
        [delegate downloadDriverDidReceiveDataOfLength:length];
    }
}

- (void)downloadDriverDidDownloadUpdate:(SPUDownloadedUpdate *)downloadedUpdate
{
    // Use a new update group for our next downloaded update
    // We could restrict this to when the appcast was downloaded in the background,
    // but it shouldn't matter.
    if (downloadedUpdate.updateItem.phasedRolloutInterval != nil) {
        [SUPhasedUpdateGroupInfo setNewUpdateGroupIdentifierForHost:_host];
    }
    
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:didDownloadUpdate:)]) {
        [updaterDelegate updater:updater didDownloadUpdate:_updateItem];
    }
    
    _resumableUpdate = downloadedUpdate;
    [self extractUpdate:downloadedUpdate];
}

- (void)deferInformationalUpdate:(SUAppcastItem *)updateItem secondaryUpdate:(SUAppcastItem * _Nullable)secondaryUpdateItem
{
    _resumableUpdate = [[SPUInformationalUpdate alloc] initWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem];
}

- (void)extractDownloadedUpdate
{
    id<SPUResumableUpdate> resumableUpdate = _resumableUpdate;
    assert(resumableUpdate != nil && [resumableUpdate isKindOfClass:[SPUDownloadedUpdate class]]);
    [self extractUpdate:(SPUDownloadedUpdate *)resumableUpdate];
}

- (void)clearDownloadedUpdate
{
    id<NSObject> downloadedUpdateObject = (_resumableUpdate != nil) ? _resumableUpdate : _downloadedUpdateForRemoval;

    if (downloadedUpdateObject == nil) {
        SULog(SULogLevelError, @"Warning: clearDownloadedUpdate called but no downloaded update is tracked");
        return;
    }

    if ([downloadedUpdateObject isKindOfClass:[SPUDownloadedUpdate class]]) {
        if (_downloadDriver == nil) {
            _downloadDriver = [[SPUDownloadDriver alloc] initWithHost:_host];
        }
        
        SPUDownloadedUpdate *downloadedUpdate = (SPUDownloadedUpdate *)downloadedUpdateObject;
        [_downloadDriver removeDownloadedUpdate:downloadedUpdate];
    }
    
    // Clear any type of resumable update
    _resumableUpdate = nil;
}

- (void)extractUpdate:(SPUDownloadedUpdate *)downloadedUpdate SPU_OBJC_DIRECT
{
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:willExtractUpdate:)]) {
        [updaterDelegate updater:updater willExtractUpdate:_updateItem];
    }
    
    // Now we have to extract the downloaded archive.
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(coreDriverDidStartExtractingUpdate)]) {
        [delegate coreDriverDidStartExtractingUpdate];
    }
    
    [_installerDriver extractDownloadedUpdate:downloadedUpdate silently:_silentInstall completion:^(NSError * _Nullable error) {
        if (error != nil) {
            if (error.code != SUInstallationAuthorizeLaterError) {
                [self clearDownloadedUpdate];
            }
            
            [self->_delegate coreDriverIsRequestingAbortUpdateWithError:error];
        } else {
            // If the installer started properly, we can't use the downloaded update archive anymore
            // Especially if the installer fails later and we try resuming the update with a missing archive file
            // We must clear the download after the installer begins using it however (in -installerDidStartInstalling)
            self->_downloadedUpdateForRemoval = downloadedUpdate;
            self->_resumableUpdate = nil;
            
            if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:didExtractUpdate:)]) {
                [updaterDelegate updater:updater didExtractUpdate:self->_updateItem];
            }
        }
    }];
}

- (void)downloadDriverDidFailToDownloadFileWithError:(NSError *)error
{
    if ([_updateItem isDeltaUpdate]) {
        SULog(SULogLevelError, @"Failed to download delta update. Falling back to regular update...");
        SULogError(error);
        
        [self fallBackAndDownloadRegularUpdate];
    } else {
        id updater = _updater;
        id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        
        if (updater != nil && [updaterDelegate respondsToSelector:@selector((updater:failedToDownloadUpdate:error:))]) {
            NSError *errorToReport = [error.userInfo objectForKey:NSUnderlyingErrorKey];
            if (errorToReport == nil) {
                errorToReport = error;
            }
            
            [updaterDelegate updater:updater failedToDownloadUpdate:_updateItem error:errorToReport];
        }
        
        [_delegate coreDriverIsRequestingAbortUpdateWithError:error];
    }
}

- (void)installerDidStartInstallingWithApplicationTerminated:(BOOL)applicationTerminated
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(installerDidStartInstallingWithApplicationTerminated:)]) {
        [delegate installerDidStartInstallingWithApplicationTerminated:applicationTerminated];
    }
}

- (void)installerDidStartExtracting
{
    // The installer has moved the archive and no longer needs the download directory
    [self clearDownloadedUpdate];
}

- (void)installerDidExtractUpdateWithProgress:(double)progress
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(installerDidExtractUpdateWithProgress:)]) {
        [delegate installerDidExtractUpdateWithProgress:progress];
    }
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately
{
    [_delegate installerDidFinishPreparationAndWillInstallImmediately:willInstallImmediately];
}

- (void)finishInstallationWithResponse:(SPUUserUpdateChoice)response displayingUserInterface:(BOOL)displayingUserInterface
{
    switch (response) {
        case SPUUserUpdateChoiceDismiss:
            [_delegate coreDriverIsRequestingAbortUpdateWithError:nil];
            break;
        case SPUUserUpdateChoiceSkip:
            [_installerDriver cancelUpdate];
            break;
        case SPUUserUpdateChoiceInstall:
            [_installerDriver installWithToolAndRelaunch:YES displayingUserInterface:displayingUserInterface];
            break;
    }
}

- (void)installerWillFinishInstallationAndRelaunch:(BOOL)relaunch
{
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil) {
        if ([updaterDelegate respondsToSelector:@selector((updater:willInstallUpdate:))]) {
            [updaterDelegate updater:updater willInstallUpdate:_updateItem];
        }
        
        if (relaunch) {
            [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:updater];
            if ([updaterDelegate respondsToSelector:@selector((updaterWillRelaunchApplication:))]) {
                [updaterDelegate updaterWillRelaunchApplication:updater];
            }
        }
    }
}

- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement
{
    id<SPUCoreBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(installerDidFinishInstallationAndRelaunched:acknowledgement:)]) {
        [delegate installerDidFinishInstallationAndRelaunched:relaunched acknowledgement:acknowledgement];
    } else {
        acknowledgement();
    }
}

- (void)installerIsRequestingAbortInstallWithError:(nullable NSError *)error
{
    [_delegate coreDriverIsRequestingAbortUpdateWithError:error];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    // A delegate may want to handle this type of error specially
    [_delegate basicDriverIsRequestingAbortUpdateWithError:error];
}

- (void)fallBackAndDownloadRegularUpdate SPU_OBJC_DIRECT
{
    SUAppcastItem *secondaryUpdateItem = _secondaryUpdateItem;
    assert(secondaryUpdateItem != nil);
    
    BOOL backgroundDownload = _downloadDriver.inBackground;
    
    // Fall back to the non-delta update. Note that we don't want to trigger another update was found event.
    _updateItem = secondaryUpdateItem;
    _secondaryUpdateItem = nil;
    
    [self downloadUpdateFromAppcastItem:secondaryUpdateItem secondaryAppcastItem:nil inBackground:backgroundDownload];
}

- (void)installerDidFailToApplyDeltaUpdate
{
    [self clearDownloadedUpdate];
    
    [self fallBackAndDownloadRegularUpdate];
}

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately error:(nullable NSError *)error
{
    [_installerDriver abortInstall];
    
    void (^basicDriverAbort)(void) = ^{
        id<SPUResumableUpdate> resumableUpdate = (error == nil || error.code == SUInstallationAuthorizeLaterError) ? self->_resumableUpdate : nil;
        
        [self->_basicDriver abortUpdateAndShowNextUpdateImmediately:shouldShowUpdateImmediately resumableUpdate:resumableUpdate error:error];
    };
    
    if (_downloadDriver != nil) {
        [_downloadDriver cleanup:^{
            basicDriverAbort();
        }];
    } else {
        basicDriverAbort();
    }
}

@end
