//
//  SPUStandardUpdaterController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SPUStandardUpdaterController.h"
#import "SPUUpdater.h"
#import "SUHost.h"
#import "SPUStandardUserDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SULocalizations.h"
#import <AppKit/AppKit.h>

// We use public instance variables instead of properties for the updater / user driver delegates
// because we want them to be connectable outlets from Interface Builder, but we do not want their setters to be invoked
// programmatically.

@interface SPUStandardUpdaterController () <NSMenuItemValidation>

// Needed for KVO
@property (nonatomic) SPUUpdater *updater;

@end

@implementation SPUStandardUpdaterController

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;

- (void)awakeFromNib
{
    // Note: awakeFromNib might be called more than once
    // We have to use awakeFromNib otherwise the delegate outlets may not be connected yet,
    // and we aren't a proper window or view controller, so we don't have a proper "did load" point
    if (_updater == nil) {
        [self _initUpdater];
        [self startUpdater];
    }
}

- (void)_initUpdater SPU_OBJC_DIRECT
{
    NSBundle *hostBundle = [NSBundle mainBundle];
    SPUStandardUserDriver *userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:self->userDriverDelegate];
    
    SPUUpdater *updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:hostBundle userDriver:userDriver delegate:self->updaterDelegate];
    [self setUpdater:updater];
    
    _userDriver = userDriver;
}

- (instancetype)initWithUpdaterDelegate:(nullable id<SPUUpdaterDelegate>)theUpdaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)theUserDriverDelegate
{
    return [self initWithStartingUpdater:YES updaterDelegate:theUpdaterDelegate userDriverDelegate:theUserDriverDelegate];
}

- (instancetype)initWithStartingUpdater:(BOOL)startUpdater updaterDelegate:(nullable id<SPUUpdaterDelegate>)theUpdaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)theUserDriverDelegate
{
    if ((self = [super init])) {
        self->updaterDelegate = theUpdaterDelegate;
        self->userDriverDelegate = theUserDriverDelegate;

        [self _initUpdater];
        
        if (startUpdater) {
            [self startUpdater];
        }
    }
    return self;
}

- (void)startUpdater
{
    NSError *updaterError = nil;
    if (![_updater startUpdater:&updaterError]) {
        SULog(SULogLevelError, @"Fatal updater error (%ld): %@", updaterError.code, updaterError.localizedDescription);
        
        // Delay the alert a bit to allow other start-up actions
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSBundle *hostBundle = [NSBundle mainBundle];
            SUHost *host = [[SUHost alloc] initWithBundle:hostBundle];
            
#if SPARKLE_COPY_LOCALIZATIONS
            NSBundle *sparkleBundle = SUSparkleBundle();
#endif
            
            // This is a developer facing error message which is never actually meant to occur in production
            // Feel free to provide localizations if you want, but it is not strictly necessary.
            // Previously, this code path used to be an abort()
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = SULocalizedStringFromTableInBundle(@"Unable to Check For Updates", SPARKLE_TABLE, sparkleBundle, nil);
            alert.informativeText = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"The updater failed to start. Please verify you have the latest version of %@ and contact the app developer if the issue still persists. Check the Console logs for more information.", SPARKLE_TABLE, sparkleBundle, nil), host.name];
            [alert runModal];
        });
    }
}

- (IBAction)checkForUpdates:(nullable id)__unused sender
{
    [_updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return _updater.canCheckForUpdates;
    }
    return YES;
}

@end

#endif
