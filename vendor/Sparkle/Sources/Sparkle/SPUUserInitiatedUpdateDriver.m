//
//  SPUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUserInitiatedUpdateDriver.h"
#import "SPUUIBasedUpdateDriver.h"
#import "SPUUserDriver.h"


#include "AppKitPrevention.h"

@interface SPUUserInitiatedUpdateDriver () <SPUUIBasedUpdateDriverDelegate>

@end

@implementation SPUUserInitiatedUpdateDriver
{
    SPUUIBasedUpdateDriver *_uiDriver;
    id<SPUUserDriver> _userDriver;
    
    void (^_updateDidShowHandler)(void);
    
    BOOL _showingUserInitiatedProgress;
    BOOL _showingUpdate;
    BOOL _aborted;
}

@synthesize showingUpdate = _showingUpdate;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SPUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater userDriver:userDriver userInitiated:YES updaterDelegate:updaterDelegate delegate:self];
        _userDriver = userDriver;
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [_uiDriver setCompletionHandler:completionBlock];
}

- (void)setUpdateShownHandler:(void (^)(void))handler
{
    _updateDidShowHandler = [handler copy];
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
    [_uiDriver setUpdateWillInstallHandler:updateWillInstallHandler];
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders
{
    _showingUserInitiatedProgress = YES;
    
    if (_updateDidShowHandler != nil) {
        _updateDidShowHandler();
        _updateDidShowHandler = nil;
    }
    
    [_userDriver showUserInitiatedUpdateCheckWithCancellation:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_showingUserInitiatedProgress) {
                [self abortUpdate];
            }
        });
    }];
    
    [_uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:NO];
}

- (void)resumeInstallingUpdate
{
    [_uiDriver resumeInstallingUpdate];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
    [_uiDriver resumeUpdate:resumableUpdate];
}

- (void)uiDriverDidShowUpdate
{
    // When a new update check has not been initiated and an update has been resumed,
    // update the driver to indicate we are showing an update to the user
    _showingUpdate = YES;
    
    if (_updateDidShowHandler != nil) {
        _updateDidShowHandler();
        _updateDidShowHandler = nil;
    }
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if (_showingUserInitiatedProgress) {
        _showingUserInitiatedProgress = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([_userDriver respondsToSelector:@selector(dismissUserInitiatedUpdateCheck)]) {
            [_userDriver dismissUserInitiatedUpdateCheck];
        }
#pragma clang diagnostic pop
    }
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    if (_showingUserInitiatedProgress) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([_userDriver respondsToSelector:@selector(dismissUserInitiatedUpdateCheck)]) {
            [_userDriver dismissUserInitiatedUpdateCheck];
        }
#pragma clang diagnostic pop
        _showingUserInitiatedProgress = NO;
    }
    _aborted = YES;
    [_uiDriver abortUpdateWithError:error showErrorToUser:YES];
}

@end
