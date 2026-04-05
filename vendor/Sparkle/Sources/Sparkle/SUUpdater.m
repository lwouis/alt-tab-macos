//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS && SPARKLE_BUILD_LEGACY_SUUPDATER

#import "SUUpdater.h"
#import "SPUUpdater.h"
#import "SPUStandardUserDriver.h"
#import "SPUStandardUserDriverDelegate.h"
#import "SPUUpdaterDelegate.h"
#import "SULog.h"
#import <AppKit/AppKit.h>

@interface SUUpdater () <SPUUpdaterDelegate, SPUStandardUserDriverDelegate>
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation SUUpdater
#pragma clang diagnostic pop
{
    SPUUpdater *_updater;
    SPUStandardUserDriver *_userDriver;
    
    void(^_postponedInstallHandler)(void);
    void(^_silentInstallHandler)(void);
    
    BOOL _delayShowingUserUpdate;
    BOOL _loggedInstallUpdatesIfAvailableWarning;
}

@synthesize delegate = _delegate;
@synthesize decryptionPassword = _decryptionPassword;

static NSMutableDictionary *sharedUpdaters = nil;

+ (SUUpdater *)sharedUpdater
{
    return [self updaterForBundle:[NSBundle mainBundle]];
}

// SUUpdater has a singleton for each bundle. We use the fact that NSBundle instances are also singletons, so we can use them as keys. If you don't trust that you can also use the identifier as key
+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle
{
    if (bundle == nil) bundle = [NSBundle mainBundle];
    id updater = [sharedUpdaters objectForKey:[NSValue valueWithNonretainedObject:bundle]];
    if (updater == nil) {
        updater = [(SUUpdater *)[[self class] alloc] initForBundle:bundle];
    }
    return updater;
}

// This is the designated initializer for SUUpdater, important for subclasses
- (instancetype)initForBundle:(NSBundle *)bundle
{
    self = [super init];
    if (bundle == nil) bundle = [NSBundle mainBundle];

    id updater = [sharedUpdaters objectForKey:[NSValue valueWithNonretainedObject:bundle]];
    if (updater)
	{
        self = updater;
	}
	else if (self)
	{
        if (sharedUpdaters == nil) {
            sharedUpdaters = [[NSMutableDictionary alloc] init];
        }
        [sharedUpdaters setObject:self forKey:[NSValue valueWithNonretainedObject:bundle]];
        
        // This bundle may not necessarily be the correct application bundle
        // Unfortunately we won't know the correct application bundle until after the delegate is set
        // See -[SUUpdater _standardUserDriverRequestsPathToRelaunch] and -[SUUpdater _pathToRelaunchForUpdater:] implemented below which resolves this
        _userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:bundle delegate:self];
        _updater = [[SPUUpdater alloc] initWithHostBundle:bundle applicationBundle:bundle userDriver:_userDriver delegate:self];
        
        NSError *updaterError = nil;
        if (![_updater startUpdater:&updaterError]) {
            SULog(SULogLevelError, @"Error: Failed to start updater with error: %@", updaterError);
        }
    }
    return self;
}

// This will be used when the updater is instantiated in a nib such as MainMenu
- (instancetype)init
{
    return [self initForBundle:[NSBundle mainBundle]];
}

- (void)resetUpdateCycle
{
    [_updater resetUpdateCycle];
}

- (NSBundle *)hostBundle
{
    return _updater.hostBundle;
}

- (NSBundle *)sparkleBundle
{
    // Use explicit class to use the correct bundle even when subclassed
    return [NSBundle bundleForClass:[SUUpdater class]];
}

- (BOOL)automaticallyChecksForUpdates
{
    return _updater.automaticallyChecksForUpdates;
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates
{
    [_updater setAutomaticallyChecksForUpdates:automaticallyChecksForUpdates];
}

- (NSTimeInterval)updateCheckInterval
{
    return _updater.updateCheckInterval;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [_updater setUpdateCheckInterval:updateCheckInterval];
}

- (NSURL *)feedURL
{
    return _updater.feedURL;
}

- (void)setFeedURL:(NSURL *)feedURL
{
    [_updater setFeedURL:feedURL];
}

- (NSString *)userAgentString
{
    return _updater.userAgentString;
}

- (void)setUserAgentString:(NSString *)userAgentString
{
    [_updater setUserAgentString:userAgentString];
}

- (NSDictionary *)httpHeaders
{
    return _updater.httpHeaders;
}

- (void)setHttpHeaders:(NSDictionary *)httpHeaders
{
    [_updater setHttpHeaders:httpHeaders];
}

- (BOOL)sendsSystemProfile
{
    return _updater.sendsSystemProfile;
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [_updater setSendsSystemProfile:sendsSystemProfile];
}

- (BOOL)automaticallyDownloadsUpdates
{
    return _updater.automaticallyDownloadsUpdates;
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyDownloadsUpdates
{
    [_updater setAutomaticallyDownloadsUpdates:automaticallyDownloadsUpdates];
}

- (IBAction)checkForUpdates:(id)__unused sender
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

- (void)checkForUpdatesInBackground
{
    if (_delayShowingUserUpdate) {
        // We don't know if SUUpdater delegate will call checkForUpdates: or checkForUpdatesInBackground
        // to bring a deferred update alert back in 1.x.
        // So if checkForUpdatesInBackground is called we will bring the update back in focus
        [self checkForUpdates:nil];
    } else {
        [_updater checkForUpdatesInBackground];
    }
}

- (NSDate *)lastUpdateCheckDate
{
    return _updater.lastUpdateCheckDate;
}

- (void)checkForUpdateInformation
{
    [_updater checkForUpdateInformation];
}

- (BOOL)updateInProgress
{
    // This is not quite true -- we may be able to check / resume an update if one is in progress
    // But this is a close enough approximation for 1.x updater API
    return _updater.sessionInProgress;
}

// Not implemented properly at the moment - leaning towards it not be in the future
// because it may be hard to implement properly (without passing a boolean flag everywhere), or
// it would require us to maintain support for an additional class used by a very few people thus far
// For now, just invoke the regular background update process if this is invoked. Could change our minds on this later.
- (void)installUpdatesIfAvailable
{
    if (!_loggedInstallUpdatesIfAvailableWarning) {
        SULog(SULogLevelError, @"-[%@ installUpdatesIfAvailable] does not function anymore.. Instead a background scheduled update check will be done.", NSStringFromClass([self class]));
        
        _loggedInstallUpdatesIfAvailableWarning = YES;
    }

    [self checkForUpdatesInBackground];
}

- (void)standardUserDriverWillShowModalAlert
{
    if ([_delegate respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
        [_delegate updaterWillShowModalAlert:self];
    }
}

- (void)standardUserDriverDidShowModalAlert
{
    if ([_delegate respondsToSelector:@selector(updaterDidShowModalAlert:)]) {
        [_delegate updaterDidShowModalAlert:self];
    }
}

- (_Nullable id <SUVersionDisplay>)standardUserDriverRequestsVersionDisplayer
{
    id <SUVersionDisplay> versionDisplayer = nil;
    if ([_delegate respondsToSelector:@selector(versionDisplayerForUpdater:)]) {
        versionDisplayer = [_delegate versionDisplayerForUpdater:self];
    }
    return versionDisplayer;
}

- (BOOL)updater:(SPUUpdater *)__unused updater mayPerformUpdateCheck:(SPUUpdateCheck)__unused updateCheck error:(NSError *__autoreleasing  _Nullable *)error
{
    BOOL updaterMayCheck = YES;
    if ([_delegate respondsToSelector:@selector(updaterMayCheckForUpdates:)]) {
        updaterMayCheck = [_delegate updaterMayCheckForUpdates:self];
    }
    return updaterMayCheck;
}

- (NSArray *)feedParametersForUpdater:(SPUUpdater *)__unused updater sendingSystemProfile:(BOOL)sendingProfile
{
    NSArray *feedParameters;
    if ([_delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) {
        feedParameters = [_delegate feedParametersForUpdater:self sendingSystemProfile:sendingProfile];
    } else {
        feedParameters = [NSArray array];
    }
    return feedParameters;
}

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)__unused updater
{
    // Be really careful not to call [self feedURL] here. That might lead us into infinite recursion.
    NSString *feedURL = nil;
    if ([_delegate respondsToSelector:@selector(feedURLStringForUpdater:)]) {
        feedURL = [_delegate feedURLStringForUpdater:self];
    }
    return feedURL;
}

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)__unused updater
{
    BOOL shouldPrompt = YES;
    if ([_delegate respondsToSelector:@selector(updaterShouldPromptForPermissionToCheckForUpdates:)]) {
        shouldPrompt = [_delegate updaterShouldPromptForPermissionToCheckForUpdates:self];
    }
    return shouldPrompt;
}

- (void)updater:(SPUUpdater *)__unused updater didFinishLoadingAppcast:(SUAppcast *)appcast
{
    if ([_delegate respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [_delegate updater:self didFinishLoadingAppcast:appcast];
    }
}

- (SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast forUpdater:(SPUUpdater *)__unused updater
{
    SUAppcastItem *bestValidUpdate = nil;
    if ([_delegate respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) {
        bestValidUpdate = [_delegate bestValidUpdateInAppcast:appcast forUpdater:self];
    }
    return bestValidUpdate;
}

- (void)updater:(SPUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)item
{
    if ([_delegate respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [_delegate updater:self didFindValidUpdate:item];
    }
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)__unused updater
{
    if ([_delegate respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [_delegate updaterDidNotFindUpdate:self];
    }
}

- (void)updater:(SPUUpdater *)__unused updater userDidMakeChoice:(SPUUserUpdateChoice)choice forUpdate:(SUAppcastItem *)updateItem state:(SPUUserUpdateState *)__unused state
{
    // This delegate callback matches 1.x behavior (even though -standardUserDriverWillFinishUpdateSession might be a better place for it)
    if ([_delegate respondsToSelector:@selector(updater:didDismissUpdateAlertPermanently:forItem:)]) {
        [_delegate updater:self didDismissUpdateAlertPermanently:(choice == SPUUserUpdateChoiceSkip) forItem:updateItem];
    }
    
    if (choice == SPUUserUpdateChoiceSkip && [_delegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
        [_delegate updater:self userDidSkipThisVersion:updateItem];
    }
}

- (BOOL)standardUserDriverShouldHandleShowingScheduledUpdate:(SUAppcastItem *)update andInImmediateFocus:(BOOL)immediateFocus
{
    if ([_delegate respondsToSelector:@selector(updaterShouldShowUpdateAlertForScheduledUpdate:forItem:)]) {
        // If the delegate returns NO and tries to show the update before
        // -standardUserDriverWillHandleShowingUpdate:forUpdate:state: is called, this is technically
        // a violation. However it is also unlikely to happen.
        return [_delegate updaterShouldShowUpdateAlertForScheduledUpdate:self forItem:update];
    } else {
        return YES;
    }
}

- (void)standardUserDriverWillHandleShowingUpdate:(BOOL)handleShowingUpdate forUpdate:(SUAppcastItem *)update state:(SPUUserUpdateState *)state
{
    if (!handleShowingUpdate) {
        _delayShowingUserUpdate = YES;
    }
}

- (void)standardUserDriverWillFinishUpdateSession
{
    _delayShowingUserUpdate = NO;
}

- (void)updater:(SPUUpdater *)__unused updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request
{
    if ([_delegate respondsToSelector:@selector(updater:willDownloadUpdate:withRequest:)]) {
        [_delegate updater:self willDownloadUpdate:item withRequest:request];
    }
}

- (void)updater:(SPUUpdater *)__unused updater didDownloadUpdate:(SUAppcastItem *)item
{
    if ([_delegate respondsToSelector:@selector(updater:didDownloadUpdate:)]) {
        [_delegate updater:self didDownloadUpdate:item];
    }
}

- (void)updater:(SPUUpdater *)__unused updater failedToDownloadUpdate:(SUAppcastItem *)item error:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(updater:failedToDownloadUpdate:error:)]) {
        [_delegate updater:self failedToDownloadUpdate:item error:error];
    }
}

- (void)userDidCancelDownload:(SPUUpdater *)__unused updater
{
    if ([_delegate respondsToSelector:@selector(userDidCancelDownload:)]) {
        [_delegate userDidCancelDownload:self];
    }
}

- (void)updater:(SPUUpdater *)updater willExtractUpdate:(SUAppcastItem *)item
{
    if ([_delegate respondsToSelector:@selector(updater:willExtractUpdate:)]) {
        [_delegate updater:self willExtractUpdate:item];
    }
}

- (void)updater:(SPUUpdater *)updater didExtractUpdate:(SUAppcastItem *)item
{
    if ([_delegate respondsToSelector:@selector(updater:didExtractUpdate:)]) {
        [_delegate updater:self didExtractUpdate:item];
    }
}

- (void)updater:(SPUUpdater *)__unused updater willInstallUpdate:(SUAppcastItem *)item
{
    if ([_delegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [_delegate updater:self willInstallUpdate:item];
    }
}

- (void)installPostponedUpdate
{
    if (_postponedInstallHandler != nil) {
        _postponedInstallHandler();
        _postponedInstallHandler = nil;
    }
}

- (BOOL)updater:(SPUUpdater *)__unused updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))installHandler
{
    BOOL shouldPostponeRelaunch = NO;
    
    if ([_delegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)]) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installPostponedUpdate)]];
        
        [invocation setSelector:@selector(installPostponedUpdate)];
        
        // This invocation will retain self, but this instance is kept alive forever by our singleton pattern anyway
        [invocation setTarget:self];

        _postponedInstallHandler = installHandler;

        shouldPostponeRelaunch = [_delegate updater:self shouldPostponeRelaunchForUpdate:item untilInvoking:invocation];
    } else if ([_delegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:)]) {
        // This API should really take a block, but not fixing a 1.x mishap now
        shouldPostponeRelaunch = [_delegate updater:self shouldPostponeRelaunchForUpdate:item];
    }
    
    return shouldPostponeRelaunch;
}

- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)__unused updater
{
    BOOL shouldRestart = YES;
    if ([_delegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)]) {
        shouldRestart = [_delegate updaterShouldRelaunchApplication:self];
    }
    return shouldRestart;
}

- (void)updaterWillRelaunchApplication:(SPUUpdater *)__unused updater
{
    if ([_delegate respondsToSelector:@selector(updaterWillRelaunchApplication:)]) {
        [_delegate updaterWillRelaunchApplication:self];
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (id<SUVersionComparison>)versionComparatorForUpdater:(SPUUpdater *)__unused updater
{
    id<SUVersionComparison> versionComparator;
    if ([_delegate respondsToSelector:@selector(versionComparatorForUpdater:)]) {
        versionComparator = [_delegate versionComparatorForUpdater:self];
    }
    return versionComparator;
}
#pragma clang diagnostic pop

// Private SPUUpdater API that allows us to defer providing an application path to relaunch
- (NSString * _Nullable)_pathToRelaunchForUpdater:(SPUUpdater *)__unused updater
{
    NSString *relaunchPath = nil;
    if ([_delegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        relaunchPath = [_delegate pathToRelaunchForUpdater:self];
    }
    return relaunchPath;
}

- (NSString *)decryptionPasswordForUpdater:(SPUUpdater *)__unused updater
{
    return _decryptionPassword;
}

- (void)finishSilentInstallation
{
    if (_silentInstallHandler != nil) {
        _silentInstallHandler();
        _silentInstallHandler = nil;
    }
}

- (BOOL)updater:(SPUUpdater *)__unused updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))immediateInstallHandler
{
    BOOL installationHandledByDelegate = NO;
    
    if ([_delegate respondsToSelector:@selector((updater:willInstallUpdateOnQuit:immediateInstallationBlock:))]) {
        [_delegate updater:self willInstallUpdateOnQuit:item immediateInstallationBlock:immediateInstallHandler];
        
        // We have to assume they will handle the installation since they implement this method
        // Not ideal, but this is why this delegate callback is deprecated
        installationHandledByDelegate = YES;
    } else if ([_delegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationInvocation:)]) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(finishSilentInstallation)]];
        
        // This invocation will retain self, but this instance is kept alive forever by our singleton pattern anyway
        [invocation setTarget:self];
        
        _silentInstallHandler = immediateInstallHandler;
        
        [_delegate updater:self willInstallUpdateOnQuit:item immediateInstallationInvocation:invocation];
        
        // We have to assume they will handle the installation since they implement this method
        // Not ideal, but this is why this delegate callback is deprecated
        installationHandledByDelegate = YES;
    }
    
    return installationHandledByDelegate;
}

- (void)updater:(SPUUpdater *)__unused updater didAbortWithError:(NSError *)error
{
    if ([_delegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
        [_delegate updater:self didAbortWithError:error];
    }
}

@end

#endif
