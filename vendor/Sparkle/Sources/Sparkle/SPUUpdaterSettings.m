//
//  SPUUpdaterSettings.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/27/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterSettings.h"
#import "SPUUpdaterSettings+Debug.h"
#import "SUHost.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

static NSString *SUAutomaticallyChecksForUpdatesKeyPath = @"automaticallyChecksForUpdates";
static NSString *SUUpdateCheckIntervalKeyPath = @"updateCheckInterval";
static NSString *SUImpatientUpdateCheckIntervalKeyPath = @"impatientUpdateCheckInterval";
static NSString *SUAutomaticallyDownloadsUpdatesKeyPath = @"automaticallyDownloadsUpdates";
static NSString *SUSendsSystemProfileKeyPath = @"sendsSystemProfile";
static NSString *SUAllowsAutomaticUpdatesOptionKeyPath = @"allowsAutomaticUpdatesOption";
static NSString *SUAllowsAutomaticUpdatesKeyPath = @"allowsAutomaticUpdates";

@implementation SPUUpdaterSettings
{
    SUHost *_host;
    
#if DEBUG
    BOOL _enableDebugUpdateCheckIntervals;
#endif
}

@synthesize automaticallyChecksForUpdates = _automaticallyChecksForUpdates;
@synthesize updateCheckInterval = _updateCheckInterval;
@synthesize impatientUpdateCheckInterval = _impatientUpdateCheckInterval;
@synthesize automaticallyDownloadsUpdates = _automaticallyDownloadsUpdates;
@synthesize sendsSystemProfile = _sendsSystemProfile;
@synthesize allowsAutomaticUpdatesOption = _allowsAutomaticUpdatesOption;
@synthesize allowsAutomaticUpdates = _allowsAutomaticUpdates;

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        
#if DEBUG
        // This one must be checked first, before checking the other settings,
        // since the others may rely on this
        _enableDebugUpdateCheckIntervals = [self currentEnableDebugUpdateCheckIntervals];
#endif
        
        _automaticallyChecksForUpdates = [self currentAutomaticallyChecksForUpdates];
        _updateCheckInterval = [self currentUpdateCheckInterval];
        _impatientUpdateCheckInterval = [self currentImpatientUpdateCheckInterval];
        _allowsAutomaticUpdatesOption = [self currentAllowsAutomaticUpdatesOption];
        _allowsAutomaticUpdates = [self currentAllowsAutomaticUpdates];
        _automaticallyDownloadsUpdates = [self currentAutomaticallyDownloadsUpdates];
        _sendsSystemProfile = [self currentSendsSystemProfile];
        
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(synchronize:) name:SUUpdateSettingsNeedsSynchronizationNotification object:nil];
        
        __weak __typeof__(self) weakSelf = self;
        [_host observeChangesFromUserDefaultKeys:[NSSet setWithArray:@[SUEnableAutomaticChecksKey, SUScheduledCheckIntervalKey, SUAutomaticallyUpdateKey, SUSendProfileInfoKey]] changeHandler:^(NSString *keyPath) {
            __typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            if ([keyPath isEqualToString:SUEnableAutomaticChecksKey]) {
                [strongSelf processCurrentAutomaticallyChecksForUpdates];
            } else if ([keyPath isEqualToString:SUScheduledCheckIntervalKey]) {
                [strongSelf processUpdateCheckInterval];
            } else if ([keyPath isEqualToString:SUAutomaticallyUpdateKey]) {
                [strongSelf processAutomaticallyDownloadsUpdates];
            } else if ([keyPath isEqualToString:SUSendProfileInfoKey]) {
                [strongSelf processSendsSystemProfile];
            }
        }];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:SUUpdateSettingsNeedsSynchronizationNotification object:_host.bundlePath];
}

- (void)processCurrentAutomaticallyChecksForUpdates SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentAutomaticallyChecksForUpdates];
    
    if (currentValue != _automaticallyChecksForUpdates) {
        NSString *updatedKeyPath = SUAutomaticallyChecksForUpdatesKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _automaticallyChecksForUpdates = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
        
        [self processAllowsAutomaticUpdates];
        [self processAutomaticallyDownloadsUpdates];
    }
}

- (void)processUpdateCheckInterval SPU_OBJC_DIRECT
{
    NSTimeInterval currentValue = [self currentUpdateCheckInterval];
    
    if (fabs(currentValue - _updateCheckInterval) >= 0.001) {
        NSString *updatedKeyPath = SUUpdateCheckIntervalKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _updateCheckInterval = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processImpatientUpdateCheckInterval SPU_OBJC_DIRECT
{
    NSTimeInterval currentValue = [self currentImpatientUpdateCheckInterval];
    
    if (fabs(currentValue - _impatientUpdateCheckInterval) >= 0.001) {
        NSString *updatedKeyPath = SUImpatientUpdateCheckIntervalKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _impatientUpdateCheckInterval = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processAllowsAutomaticUpdatesOption SPU_OBJC_DIRECT
{
    NSNumber *currentValue = [self currentAllowsAutomaticUpdatesOption];
    
    if (((currentValue != nil) != (_allowsAutomaticUpdatesOption != nil)) || (currentValue.boolValue != _allowsAutomaticUpdatesOption.boolValue)) {
        NSString *updatedKeyPath = SUAllowsAutomaticUpdatesOptionKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _allowsAutomaticUpdatesOption = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processAllowsAutomaticUpdates SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentAllowsAutomaticUpdates];
    
    if (currentValue != _allowsAutomaticUpdates) {
        NSString *updatedKeyPath = SUAllowsAutomaticUpdatesKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _allowsAutomaticUpdates = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processAutomaticallyDownloadsUpdates SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentAutomaticallyDownloadsUpdates];
    
    if (currentValue != _automaticallyDownloadsUpdates) {
        NSString *updatedKeyPath = SUAutomaticallyDownloadsUpdatesKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _automaticallyDownloadsUpdates = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processSendsSystemProfile SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentSendsSystemProfile];
    
    if (currentValue != _sendsSystemProfile) {
        NSString *updatedKeyPath = SUSendsSystemProfileKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _sendsSystemProfile = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)synchronize:(NSNotification *)notification
{
    NSString *bundlePath = notification.userInfo[SUUpdateBundlePathUserInfoKey];
    if (![bundlePath isEqualToString:_host.bundlePath]) {
        return;
    }
    
#if DEBUG
    // This one must be checked first, before checking the other settings,
    // since the others may rely on this
    _enableDebugUpdateCheckIntervals = [self currentEnableDebugUpdateCheckIntervals];
#endif
    
    [self processCurrentAutomaticallyChecksForUpdates];
    [self processUpdateCheckInterval];
    [self processImpatientUpdateCheckInterval];
    [self processAllowsAutomaticUpdatesOption];
    [self processAllowsAutomaticUpdates];
    [self processAutomaticallyDownloadsUpdates];
    [self processSendsSystemProfile];
}

- (BOOL)currentAutomaticallyChecksForUpdates SPU_OBJC_DIRECT
{
    // Don't automatically update when the check interval is 0, to be compatible with 1.1 settings.
    if ((NSInteger)[self currentUpdateCheckInterval] == 0) {
        return NO;
    }
    return [_host boolForKey:SUEnableAutomaticChecksKey];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyCheckForUpdates
{
    [self willChangeValueForKey:SUAutomaticallyChecksForUpdatesKeyPath];
    
    _automaticallyChecksForUpdates = automaticallyCheckForUpdates;
    [_host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
    
    [self didChangeValueForKey:SUAutomaticallyChecksForUpdatesKeyPath];
    
    // Hack to support backwards compatibility with older Sparkle versions, which supported
    // disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && (NSInteger)[self currentUpdateCheckInterval] == 0) {
        [self setUpdateCheckInterval:[self defaultUpdateCheckInterval]];
    } else {
        [NSNotificationCenter.defaultCenter postNotificationName:SUUpdateAutomaticCheckSettingChangedNotification object:nil userInfo:@{SUUpdateBundlePathUserInfoKey: _host.bundlePath}];
    }
    
    [self processAllowsAutomaticUpdates];
    [self processAutomaticallyDownloadsUpdates];
}

+ (BOOL)automaticallyNotifiesObserversOfAutomaticallyChecksForUpdates
{
    return NO;
}

- (NSTimeInterval)currentUpdateCheckInterval SPU_OBJC_DIRECT
{
    // Find the stored check interval. User defaults override Info.plist.
    NSNumber *intervalValue = [_host doubleNumberForKey:SUScheduledCheckIntervalKey];
    if (intervalValue == nil) {
        return [self defaultUpdateCheckInterval];
    }
    
    return intervalValue.doubleValue;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [self willChangeValueForKey:SUUpdateCheckIntervalKeyPath];
    
    _updateCheckInterval = updateCheckInterval;
    [_host setObject:@(updateCheckInterval) forUserDefaultsKey:SUScheduledCheckIntervalKey];
    
    [self didChangeValueForKey:SUUpdateCheckIntervalKeyPath];
    
    if ((NSInteger)updateCheckInterval == 0) { // For compatibility with 1.1's settings.
        [self setAutomaticallyChecksForUpdates:NO];
    } else {
        [NSNotificationCenter.defaultCenter postNotificationName:SUUpdateAutomaticCheckSettingChangedNotification object:nil userInfo:@{SUUpdateBundlePathUserInfoKey: _host.bundlePath}];
    }
}

- (NSTimeInterval)currentImpatientUpdateCheckInterval SPU_OBJC_DIRECT
{
    NSNumber *intervalValue = [_host doubleNumberForInfoDictionaryKey:SUScheduledImpatientCheckIntervalKey];
    if (intervalValue == nil) {
        return [self defaultImpatientUpdateCheckInterval];
    }
    
    return intervalValue.doubleValue;
}

+ (BOOL)automaticallyNotifiesObserversOfUpdateCheckInterval
{
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversOfImpatientUpdateCheckInterval
{
    return NO;
}

- (NSNumber * _Nullable)currentAllowsAutomaticUpdatesOption SPU_OBJC_DIRECT
{
    NSNumber *developerAllowsAutomaticUpdates = [_host boolNumberForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
    return developerAllowsAutomaticUpdates;
}

+ (BOOL)automaticallyNotifiesObserversOfAllowsAutomaticUpdatesOption
{
    return NO;
}

// This depends on currentAllowsAutomaticUpdatesOption and currentAutomaticallyChecksForUpdates and must be processed afterwards
- (BOOL)currentAllowsAutomaticUpdates
{
    return (_allowsAutomaticUpdatesOption == nil) ? _automaticallyChecksForUpdates : _allowsAutomaticUpdatesOption.boolValue;
}

+ (BOOL)automaticallyNotifiesObserversOfAllowsAutomaticUpdates
{
    return NO;
}

// This depends on currentAllowsAutomaticUpdates and must be processed afterwards
- (BOOL)currentAutomaticallyDownloadsUpdates SPU_OBJC_DIRECT
{
    return _allowsAutomaticUpdates && [_host boolForKey:SUAutomaticallyUpdateKey];
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyDownloadsUpdates
{
    if (![self allowsAutomaticUpdates]) {
        return;
    }
    
    [self willChangeValueForKey:SUAutomaticallyDownloadsUpdatesKeyPath];
    
    _automaticallyDownloadsUpdates = automaticallyDownloadsUpdates;
    [_host setBool:automaticallyDownloadsUpdates forUserDefaultsKey:SUAutomaticallyUpdateKey];
    
    [self didChangeValueForKey:SUAutomaticallyDownloadsUpdatesKeyPath];
}

+ (BOOL)automaticallyNotifiesObserversOfAutomaticallyDownloadsUpdates
{
    return NO;
}

- (BOOL)currentSendsSystemProfile SPU_OBJC_DIRECT
{
    return [_host boolForKey:SUSendProfileInfoKey];
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [self willChangeValueForKey:SUSendsSystemProfileKeyPath];
    
    _sendsSystemProfile = sendsSystemProfile;
    [_host setBool:sendsSystemProfile forUserDefaultsKey:SUSendProfileInfoKey];
    
    [self didChangeValueForKey:SUSendsSystemProfileKeyPath];
}

+ (BOOL)automaticallyNotifiesObserversOfSendsSystemProfile
{
    return NO;
}

#if DEBUG
// This is only used in DEBUG and is meant for the Sparkle Test App
- (BOOL)currentEnableDebugUpdateCheckIntervals
{
    return [_host boolForInfoDictionaryKey:@"_SUEnableDebugUpdateCheckIntervals"];
}
#endif

- (NSTimeInterval)minimumUpdateCheckInterval
{
#if DEBUG
    if (_enableDebugUpdateCheckIntervals) {
        // 1 minute
        return 60;
    }
#endif
    
    // 1 hour
    return (60 * 60);
}

- (uint64_t)leewayUpdateCheckInterval
{
#if DEBUG
    if (_enableDebugUpdateCheckIntervals) {
        // 1 second
        return 1;
    }
#endif
    
    // 15 seconds
    return 15;
}

- (NSTimeInterval)defaultUpdateCheckInterval SPU_OBJC_DIRECT
{
#if DEBUG
    if (_enableDebugUpdateCheckIntervals) {
        // 1 minute
        return 60;
    }
#endif
    
    // 1 day
    return (60 * 60 * 24);
}

// If the update has already been automatically downloaded, we normally don't want to bug the user about the update
// However if the user has gone a very long time without quitting an application, we will notify them
- (NSTimeInterval)defaultImpatientUpdateCheckInterval SPU_OBJC_DIRECT
{
#if DEBUG
    if (_enableDebugUpdateCheckIntervals) {
        // 2 minutes
        return (60 * 2);
    }
#endif
    
    // 1 week
    return (60 * 60 * 24 * 7);
}

- (NSTimeInterval)standardUIScheduledUpdateIdleEventLeewayInterval
{
#if DEBUG
    if (_enableDebugUpdateCheckIntervals) {
        // 30 seconds
        return 30.0;
    }
#endif
    
    // 5 minutes
    return (5 * 60.0);
}

@end
