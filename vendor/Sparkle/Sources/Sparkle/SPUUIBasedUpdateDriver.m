//
//  SPUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUIBasedUpdateDriver.h"
#import "SPUCoreBasedUpdateDriver.h"
#import "SPUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SPUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"
#import "SPUDownloadData.h"
#import "SPUDownloadDataPrivate.h"
#import "SPUExtractSignedFeed.h"
#import "SPUResumableUpdate.h"
#import "SPUDownloadDriver.h"
#import "SPUSkippedUpdate.h"
#import "SPUUserUpdateState+Private.h"
#import "SUAppcastItem+Private.h"
#import "SUSignatures.h"
#import "SUSignatureVerifier.h"
#import "SPUVerifierInformation.h"
#import "SULocalizations.h"


#include "AppKitPrevention.h"

// Private class for downloading release notes
@interface SPUReleaseNotesDriver: NSObject <SPUDownloadDriverDelegate>
@end

@implementation SPUReleaseNotesDriver
{
    SPUDownloadDriver *_downloadDriver;
    SUHost *_host;
    SUSignatures *_signatures;
    
    void (^_completionHandler)(SPUDownloadData * _Nullable, NSError  * _Nullable);
    
    uint64_t _contentLength;
}

- (instancetype)initWithReleaseNotesURL:(NSURL *)releaseNotesURL contentLength:(uint64_t)contentLength signatures:(SUSignatures * _Nullable)signatures httpHeaders:(NSDictionary * _Nullable)httpHeaders userAgent:(NSString * _Nullable)userAgent host:(SUHost *)host completionHandler:(void (^)(SPUDownloadData * _Nullable, NSError * _Nullable))completionHandler SPU_OBJC_DIRECT
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _signatures = signatures;
        _contentLength = contentLength;
        _downloadDriver = [[SPUDownloadDriver alloc] initWithRequestURL:releaseNotesURL host:host userAgent:userAgent httpHeaders:httpHeaders inBackground:NO delegate:self];
        _completionHandler = [completionHandler copy];
    } else {
        assert(false);
    }
    return self;
}

- (void)startDownload SPU_OBJC_DIRECT
{
    [_downloadDriver downloadFile];
}

- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadDataToValidate
{
    if (_completionHandler != nil) {
        SPUDownloadData *downloadDataToPassToUserDriver;
        
        // Strip out any sign warning comment prefix for markdown data so that user drivers
        // will not have to deal with parsing them (if their markdown parsers don't handle decoding HTML)
        NSString *MIMEType = downloadDataToValidate.MIMEType;
        NSString *pathExtension = _downloadDriver.request.URL.pathExtension;
        if ([MIMEType isEqualToString:@"text/markdown"] || [MIMEType isEqualToString:@"text/x-markdown"] ||
            [pathExtension caseInsensitiveCompare:@"md"] == NSOrderedSame || [pathExtension caseInsensitiveCompare:@"markdown"] == NSOrderedSame) {
            
            NSData *contentData = SPUExtractReleaseNotesContent(downloadDataToValidate.data);
            if (contentData.length != downloadDataToValidate.data.length) {
                downloadDataToPassToUserDriver = [[SPUDownloadData alloc] initWithData:contentData URL:downloadDataToValidate.URL textEncodingName:downloadDataToValidate.textEncodingName MIMEType:downloadDataToValidate.MIMEType];
            } else {
                downloadDataToPassToUserDriver = downloadDataToValidate;
            }
        } else {
            downloadDataToPassToUserDriver = downloadDataToValidate;
        }
        
        if (_host.requiresSignedAppcast) {
            SUSignatureVerifier *signatureVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:_host.publicKeys];
            SPUVerifierInformation *verifierInformation = [[SPUVerifierInformation alloc] initWithExpectedVersion:nil expectedContentLength:_contentLength];
            verifierInformation.actualContentLength = downloadDataToValidate.data.length;
            
            NSError *verifierError = nil;
            if (![signatureVerifier verifyData:downloadDataToValidate.data signatures:_signatures fileKind:@"release notes" verifierInformation:verifierInformation error:&verifierError]) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"The release notes is improperly signed and could not be validated. Please contact the app developer for more information.", SPARKLE_TABLE, SUSparkleBundle(), nil)}];
                
                if (verifierError != nil) {
                    [userInfo setObject:verifierError forKey:NSUnderlyingErrorKey];
                }
                
                _completionHandler(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]);
            } else {
                _completionHandler(downloadDataToPassToUserDriver, nil);
            }
        } else {
            _completionHandler(downloadDataToPassToUserDriver, nil);
        }
        
        _completionHandler = nil;
    }
}

- (void)downloadDriverDidFailToDownloadFileWithError:(nonnull NSError *)error
{
    if (_completionHandler != nil) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred while downloading the release notes.", SPARKLE_TABLE, SUSparkleBundle(), nil)}];
        
        if (error != nil) {
            [userInfo setObject:error forKey:NSUnderlyingErrorKey];
        }
        
        _completionHandler(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]);
        _completionHandler = nil;
    }
}

- (void)cleanup:(void (^)(void))cleanupHandler SPU_OBJC_DIRECT
{
    _completionHandler = nil;
    [_downloadDriver cleanup:cleanupHandler];
}

@end

@interface SPUUIBasedUpdateDriver() <SPUCoreBasedUpdateDriverDelegate>
@end

@implementation SPUUIBasedUpdateDriver
{
    SPUCoreBasedUpdateDriver *_coreDriver;
    SUHost *_host;
    id<SPUUserDriver> _userDriver;
    SPUReleaseNotesDriver *_releaseNotesDriver;
    NSDictionary *_httpHeaders;
    NSString *_userAgent;
    
    __weak id _updater;
    __weak id<SPUUpdaterDelegate> _updaterDelegate;
    __weak id<SPUUIBasedUpdateDriverDelegate> _delegate;
    
    BOOL _userInitiated;
    BOOL _resumingInstallingUpdate;
    BOOL _resumingDownloadedInfoOrUpdate;
}

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver userInitiated:(BOOL)userInitiated updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUUIBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
        _delegate = delegate;
        _updater = updater;
        _userInitiated = userInitiated;
        _updaterDelegate = updaterDelegate;
        _host = host;
        
        SPUUpdateCheck updateCheck = userInitiated ? SPUUpdateCheckUpdates : SPUUpdateCheckUpdatesInBackground;
        
        _coreDriver = [[SPUCoreBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle updateCheck:updateCheck updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [_coreDriver setCompletionHandler:completionBlock];
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
    [_coreDriver setUpdateWillInstallHandler:updateWillInstallHandler];
}

- (void)_clearSkippedUpdatesIfUserInitiated SPU_OBJC_DIRECT
{
    if (_userInitiated) {
        [SPUSkippedUpdate clearSkippedUpdateForHost:_host];
    }
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background
{
    _httpHeaders = httpHeaders;
    _userAgent = userAgent;
    
    [self _clearSkippedUpdatesIfUserInitiated];
    
    [_coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:background requiresSilentInstall:NO];
}

- (void)resumeInstallingUpdate
{
    [self _clearSkippedUpdatesIfUserInitiated];
    
    _resumingInstallingUpdate = YES;
    [_coreDriver resumeInstallingUpdate];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
    [self _clearSkippedUpdatesIfUserInitiated];
    
    _resumingDownloadedInfoOrUpdate = YES;
    [_coreDriver resumeUpdate:resumableUpdate];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    id<SPUUIBasedUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem
{
    id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    id<SPUUIBasedUpdateDriverDelegate> delegate = _delegate;
    
    SPUUserUpdateStage stage;
    // Major upgrades and information only updates are not downloaded automatically, as well as feeds that failed signing validation
    if (_resumingDownloadedInfoOrUpdate && !updateItem.majorUpgrade && !updateItem.informationOnlyUpdate && updateItem.signingValidationStatus != SPUAppcastSigningValidationStatusFailed) {
        stage = SPUUserUpdateStageDownloaded;
    } else if (_resumingInstallingUpdate) {
        stage = SPUUserUpdateStageInstalling;
    } else {
        stage = SPUUserUpdateStageNotDownloaded;
    }
    
    SPUUserUpdateState *state = [[SPUUserUpdateState alloc] initWithStage:stage userInitiated:_userInitiated];
    
    [_userDriver showUpdateFoundWithAppcastItem:updateItem state:state reply:^(SPUUserUpdateChoice userChoice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            // Rule out invalid choices
            SPUUserUpdateChoice validatedChoice;
            if (updateItem.isInformationOnlyUpdate && userChoice == SPUUserUpdateChoiceInstall) {
                validatedChoice = SPUUserUpdateChoiceDismiss;
            } else {
                validatedChoice = userChoice;
            }
            
            id updater = self->_updater;
            if (updater != nil) {
                if ([updaterDelegate respondsToSelector:@selector(updater:userDidMakeChoice:forUpdate:state:)]) {
                    [updaterDelegate updater:updater userDidMakeChoice:validatedChoice forUpdate:updateItem state:state];
                } else if (validatedChoice == SPUUserUpdateChoiceSkip && [updaterDelegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    [updaterDelegate updater:updater userDidSkipThisVersion:updateItem];
    #pragma clang diagnostic pop
                }
            }
            
            switch (validatedChoice) {
                case SPUUserUpdateChoiceInstall: {
                    switch (stage) {
                        case SPUUserUpdateStageDownloaded:
                            [self->_coreDriver extractDownloadedUpdate];
                            break;
                        case SPUUserUpdateStageInstalling:
                            [self->_coreDriver finishInstallationWithResponse:validatedChoice displayingUserInterface:YES];
                            break;
                        case SPUUserUpdateStageNotDownloaded:
                            [self->_coreDriver downloadUpdateFromAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem inBackground:NO];
                            break;
                    }
                    break;
                }
                case SPUUserUpdateChoiceSkip: {
                    [SPUSkippedUpdate skipUpdate:updateItem host:self->_host];
                    
                    switch (stage) {
                        case SPUUserUpdateStageDownloaded:
                        case SPUUserUpdateStageNotDownloaded:
                            // Informational and major updates can be resumed too, so make sure we check
                            // self->_resumingDownloadedInfoOrUpdate instead of the stage we pass to user driver
                            if (self->_resumingDownloadedInfoOrUpdate) {
                                [self->_coreDriver clearDownloadedUpdate];
                            }
                            
                            [delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                            
                            break;
                        case SPUUserUpdateStageInstalling:
                            [self->_coreDriver finishInstallationWithResponse:validatedChoice displayingUserInterface:YES];
                            break;
                    }
                    
                    break;
                }
                case SPUUserUpdateChoiceDismiss: {
                    switch (stage) {
                        case SPUUserUpdateStageDownloaded:
                        case SPUUserUpdateStageNotDownloaded: {
                            [self->_delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                            break;
                        }
                        case SPUUserUpdateStageInstalling: {
                            [self->_coreDriver finishInstallationWithResponse:validatedChoice displayingUserInterface:YES];
                            break;
                        }
                    }
                    
                    break;
                }
            }
        });
    }];
    
    if ([delegate respondsToSelector:@selector(uiDriverDidShowUpdate)]) {
        [delegate uiDriverDidShowUpdate];
    }
    
    if (updateItem.releaseNotesURL != nil && (![updaterDelegate respondsToSelector:@selector(updater:shouldDownloadReleaseNotesForUpdate:)] || [updaterDelegate updater:_updater shouldDownloadReleaseNotesForUpdate:updateItem])) {
        
        __weak __typeof__(self) weakSelf = self;
        _releaseNotesDriver = [[SPUReleaseNotesDriver alloc] initWithReleaseNotesURL:updateItem.releaseNotesURL contentLength:updateItem.releaseNotesContentLength signatures:updateItem.releaseNotesSignatures httpHeaders:_httpHeaders userAgent:_userAgent host:_host completionHandler:^(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error) {
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                id <SPUUserDriver> userDriver = strongSelf->_userDriver;
                if (downloadData != nil) {
                    [userDriver showUpdateReleaseNotesWithDownloadData:(SPUDownloadData * _Nonnull)downloadData];
                } else {
                    [userDriver showUpdateReleaseNotesFailedToDownloadWithError:(NSError * _Nonnull)error];
                }
            }
        }];
        
        [_releaseNotesDriver startDownload];
    }
}

- (void)downloadDriverWillBeginDownload
{
    void (^cancelDownload)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            id<SPUUpdaterDelegate> updaterDelegate = self->_updaterDelegate;
            if ([updaterDelegate respondsToSelector:@selector((userDidCancelDownload:))]) {
                [updaterDelegate userDidCancelDownload:self->_updater];
            }
            
            [self->_delegate uiDriverIsRequestingAbortUpdateWithError:nil];
        });
    };
    
    [_userDriver showDownloadInitiatedWithCancellation:cancelDownload];
}

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    [_userDriver showDownloadDidReceiveExpectedContentLength:expectedContentLength];
}

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length
{
    [_userDriver showDownloadDidReceiveDataOfLength:length];
}

- (void)coreDriverDidStartExtractingUpdate
{
    [_userDriver showDownloadDidStartExtractingUpdate];
}

- (void)installerDidStartInstallingWithApplicationTerminated:(BOOL)applicationTerminated
{
    if ([_userDriver respondsToSelector:@selector(showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:)]) {
        __weak __typeof__(self) weakSelf = self;
        [_userDriver showInstallingUpdateWithApplicationTerminated:applicationTerminated retryTerminatingApplication:^{
            if (!applicationTerminated) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil) {
                        [strongSelf->_coreDriver finishInstallationWithResponse:SPUUserUpdateChoiceInstall displayingUserInterface:YES];
                    }
                });
            }
        }];
    } else if ([_userDriver respondsToSelector:@selector(showInstallingUpdateWithApplicationTerminated:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_userDriver showInstallingUpdateWithApplicationTerminated:applicationTerminated];
#pragma clang diagnostic pop
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([_userDriver respondsToSelector:@selector(showInstallingUpdate)]) {
            [_userDriver showInstallingUpdate];
        }
        
        if (!applicationTerminated) {
            if ([_userDriver respondsToSelector:@selector(showSendingTerminationSignal)]) {
                [_userDriver showSendingTerminationSignal];
            }
        }
#pragma clang diagnostic pop
    }
}

- (void)installerDidExtractUpdateWithProgress:(double)progress
{
    [_userDriver showExtractionReceivedProgress:progress];
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately
{
    if (!willInstallImmediately) {
        [_userDriver showReadyToInstallAndRelaunch:^(SPUUserUpdateChoice choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_coreDriver finishInstallationWithResponse:choice displayingUserInterface:YES];
            });
        }];
    }
}

- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement
{
    if ([_userDriver respondsToSelector:@selector(showUpdateInstalledAndRelaunched:acknowledgement:)]) {
        [_userDriver showUpdateInstalledAndRelaunched:relaunched acknowledgement:acknowledgement];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_userDriver showUpdateInstallationDidFinishWithAcknowledgement:acknowledgement];
#pragma clang diagnostic pop
    }
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    // A delegate may want to handle this type of error specially
    [_delegate basicDriverIsRequestingAbortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    // A delegate may want to handle this type of error specially
    [_delegate coreDriverIsRequestingAbortUpdateWithError:error];
}

- (void)_abortUpdateWithError:(nullable NSError *)error showErrorToUser:(BOOL)showErrorToUser SPU_OBJC_DIRECT
{
    void (^abortUpdate)(void) = ^{
        if (showErrorToUser) {
            [self->_userDriver dismissUpdateInstallation];
        }
        [self->_coreDriver abortUpdateAndShowNextUpdateImmediately:NO error:error];
    };
    
    if (error != nil && showErrorToUser) {
        NSError *nonNullError = error;
        
        if (error.code == SUNoUpdateError) {
            if ([_userDriver respondsToSelector:@selector(showUpdateNotFoundWithError:acknowledgement:)]) {
                [_userDriver showUpdateNotFoundWithError:(NSError * _Nonnull)error acknowledgement:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        abortUpdate();
                    });
                }];
            } else if ([_userDriver respondsToSelector:@selector(showUpdateNotFoundWithAcknowledgement:)]) {
                // Eventually we should remove this fallback once clients adopt -showUpdateNotFoundWithError:acknowledgement:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [_userDriver showUpdateNotFoundWithAcknowledgement:^{
#pragma clang diagnostic pop
                    dispatch_async(dispatch_get_main_queue(), ^{
                        abortUpdate();
                    });
                }];
            }
        } else if (error.code == SUInstallationCanceledError || error.code == SUInstallationAuthorizeLaterError) {
            abortUpdate();
        } else {
            [_userDriver showUpdaterError:nonNullError acknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    abortUpdate();
                });
            }];
        }
    } else {
        abortUpdate();
    }
}

- (void)abortUpdateWithError:(nullable NSError *)error showErrorToUser:(BOOL)showErrorToUser
{
    if (_releaseNotesDriver != nil) {
        [_releaseNotesDriver cleanup:^{
            [self _abortUpdateWithError:error showErrorToUser:showErrorToUser];
        }];
    } else {
        [self _abortUpdateWithError:error showErrorToUser:showErrorToUser];
    }
}

@end
