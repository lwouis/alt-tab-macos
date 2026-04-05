//
//  SPUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUProbingUpdateDriver.h"
#import "SPUBasicUpdateDriver.h"


#include "AppKitPrevention.h"

@interface SPUProbingUpdateDriver () <SPUBasicUpdateDriverDelegate>

@end

@implementation SPUProbingUpdateDriver
{
    SPUBasicUpdateDriver *_basicDriver;
    id<SPUResumableUpdate> _resumableUpdate;
}

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _basicDriver = [[SPUBasicUpdateDriver alloc] initWithHost:host updateCheck:SPUUpdateCheckUpdateInformation updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [_basicDriver setCompletionHandler:completionBlock];
}

- (void)setUpdateShownHandler:(void (^)(void))updateShownHandler
{
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders
{
    [_basicDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES];
}

- (void)resumeInstallingUpdate
{
    [_basicDriver resumeInstallingUpdate];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
    _resumableUpdate = resumableUpdate;
    
    [_basicDriver resumeUpdate:resumableUpdate];
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)__unused appcastItem secondaryAppcastItem:(SUAppcastItem * _Nullable)__unused secondaryAppcastItem systemDomain:(NSNumber * _Nullable)__unused systemDomain
{
    // Stop as soon as we have an answer
    [self abortUpdate];
}

- (BOOL)showingUpdate
{
    return NO;
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    [_basicDriver abortUpdateAndShowNextUpdateImmediately:NO resumableUpdate:_resumableUpdate error:error];
}

@end
