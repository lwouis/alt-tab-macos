//
//  SPUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUScheduledUpdateDriver.h"
#import "SUHost.h"
#import "SUErrors.h"
#import "SPUUpdaterDelegate.h"
#import "SPUUserDriver.h"


#include "AppKitPrevention.h"

@interface SPUScheduledUpdateDriver() <SPUUIBasedUpdateDriverDelegate>

@end

@implementation SPUScheduledUpdateDriver
{
    SPUUIBasedUpdateDriver *_uiDriver;
    
    void (^_updateDidShowHandler)(void);
    
    BOOL _showedUpdate;
}

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SPUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater userDriver:userDriver userInitiated:NO updaterDelegate:updaterDelegate delegate:self];
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
    [_uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES];
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
    _showedUpdate = YES;
    
    if (_updateDidShowHandler != nil) {
        _updateDidShowHandler();
    }
}

- (BOOL)showingUpdate
{
    return _showedUpdate;
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *) error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *) error
{
    [self abortUpdateWithError:error];
}

- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    [_uiDriver abortUpdateWithError:error showErrorToUser:_showedUpdate];
}

@end
