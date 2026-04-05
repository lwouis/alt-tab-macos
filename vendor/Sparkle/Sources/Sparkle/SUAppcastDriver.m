//
//  SUAppcastDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUAppcastDriver.h"
#import "SUAppcast.h"
#import "SUAppcast+Private.h"
#import "SUAppcastItem.h"
#import "SUAppcastItem+Private.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SPUUpdaterDelegate.h"
#import "SUHost.h"
#import "SPUSkippedUpdate.h"
#import "SUConstants.h"
#import "SUPhasedUpdateGroupInfo.h"
#import "SULog.h"
#import "SPUDownloadDriver.h"
#import "SPUDownloadData.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SPUAppcastItemStateResolver.h"
#import "SPUAppcastItemStateResolver+Private.h"
#import "SPUAppcastItemState.h"
#import "SUSignatureVerifier.h"
#import "SPUExtractSignedFeed.h"
#import "SUSignatures.h"
#import "SPUVerifierInformation.h"


#include "AppKitPrevention.h"

#define SUInitialFailedFeedSigningValidationDateKey @"SUInitialFailedFeedSigningValidationDate"

#define DEFAULT_APPCAST_FAILURE_EXPIRATION_INTERVAL 1728000 // 20 days

@interface SUAppcastDriver () <SPUDownloadDriverDelegate>
@end

@implementation SUAppcastDriver
{
    SUHost *_host;
    SPUDownloadDriver *_downloadDriver;
    
    __weak id _updater;
    __weak id <SPUUpdaterDelegate> _updaterDelegate;
    __weak id <SUAppcastDriverDelegate> _delegate;
}

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SUAppcastDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _delegate = delegate;
    }
    return self;
}

- (void)loadAppcastFromURL:(NSURL *)appcastURL userAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background
{
    assert(NSThread.isMainThread);
    
    NSMutableDictionary *requestHTTPHeaders = [NSMutableDictionary dictionary];
    if (httpHeaders != nil) {
        [requestHTTPHeaders addEntriesFromDictionary:(NSDictionary * _Nonnull)httpHeaders];
    }
    requestHTTPHeaders[@"Accept"] = @"application/rss+xml,*/*;q=0.1";
    
    _downloadDriver = [[SPUDownloadDriver alloc] initWithRequestURL:appcastURL host:_host userAgent:userAgent httpHeaders:requestHTTPHeaders inBackground:background delegate:self];
    
    [_downloadDriver downloadFile];
}

- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadData
{
    SPUAppcastItemStateResolver *stateResolver = [[SPUAppcastItemStateResolver alloc] initWithHostVersion:_host.version applicationVersionComparator:[self versionComparator] standardVersionComparator:[SUStandardVersionComparator defaultComparator]];
    
    NSData *downloadedAppcastData = downloadData.data;
    
    id<SUAppcastDriverDelegate> delegate = _delegate;
    
    NSDate *currentDate = [NSDate date];
    
    // Verify feed if appcast signing is required
    SPUAppcastSigningValidationStatus appcastSigningValidationStatus;
    NSData *verifiedAppcastData;
    NSError *verifyAppcastDataFailureError = nil;
    if (_host.requiresSignedAppcast) {
        // Extract appcast content without signing information and prepare verification information
        SUSignatureVerifier *signatureVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:_host.publicKeys];
        
        NSString *edSignatureBase64 = nil;
        uint64_t contentLength = 0;
        verifiedAppcastData = SPUExtractAppcastContent(downloadedAppcastData, &edSignatureBase64, &contentLength);
        
        SUSignatures *signatures = [[SUSignatures alloc] initWithEd:edSignatureBase64
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                               dsa:nil
#endif
                    ];
        
        SPUVerifierInformation *verifierInformation = [[SPUVerifierInformation alloc] initWithExpectedVersion:nil expectedContentLength:contentLength];
        verifierInformation.actualContentLength = verifiedAppcastData.length;
        
        // If signature verification fails, we will record the initial date it failed
        // If a significant period of time passes with verification still failing, we may operate in a 'safe' mode as fallback
        // and allow an app to be updated through key rotation
        
        // If main bundle and host bundle differ, use the main bundle (updater) with a host bundle identifier to record the validation failure date
        // This ensures external updaters record this date separately from an app updating itself.
        SUHost *hostForFailedSigningValidationDate;
        
        NSString *initialFailedFeedSigningValidationDateKey;
        NSBundle *mainBundle = NSBundle.mainBundle;
        if ([mainBundle isEqual:_host.bundle]) {
            hostForFailedSigningValidationDate = _host;
            initialFailedFeedSigningValidationDateKey = SUInitialFailedFeedSigningValidationDateKey;
        } else {
            hostForFailedSigningValidationDate = [[SUHost alloc] initWithBundle:mainBundle];
            
            NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
            initialFailedFeedSigningValidationDateKey = (hostBundleIdentifier != nil) ? [SUInitialFailedFeedSigningValidationDateKey"_" stringByAppendingString:hostBundleIdentifier] : nil;
        }
        
        NSError *verifyAppcastDataInnerError = nil;
        if (![signatureVerifier verifyData:verifiedAppcastData signatures:signatures fileKind:@"appcast" verifierInformation:verifierInformation error:&verifyAppcastDataInnerError]) {
            // Feed validation failed. Proceed to check if we can operate in safe mode if feed failure expiration interval has passed.
            
            NSNumber *failureExpirationIntervalSetting = [_host doubleNumberForInfoDictionaryKey:SUSignedFeedFailureExpirationIntervalKey];
            
            NSTimeInterval failureExpirationInterval = (failureExpirationIntervalSetting == nil) ? DEFAULT_APPCAST_FAILURE_EXPIRATION_INTERVAL : failureExpirationIntervalSetting.doubleValue;
            
            BOOL canRecoverFromSigningValidationFailure;
            if (initialFailedFeedSigningValidationDateKey == nil || fpclassify(failureExpirationInterval) == FP_ZERO) {
                canRecoverFromSigningValidationFailure = NO;
            } else {
                NSDate *firstFailedSigningValidationDate = [hostForFailedSigningValidationDate objectForUserDefaultsKey:initialFailedFeedSigningValidationDateKey ofClass:NSDate.class];
                
                if (firstFailedSigningValidationDate == nil) {
                    // Record first signing validation date
                    [hostForFailedSigningValidationDate setObject:currentDate forUserDefaultsKey:initialFailedFeedSigningValidationDateKey];
                    canRecoverFromSigningValidationFailure = NO;
                } else {
                    canRecoverFromSigningValidationFailure = ([currentDate timeIntervalSinceDate:firstFailedSigningValidationDate] >= failureExpirationInterval);
                }
            }
            
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:SULocalizedStringFromTableInBundle(@"The update feed is improperly signed and could not be validated. Please try again later or contact the app developer.", SPARKLE_TABLE, SUSparkleBundle(), nil) forKey:NSLocalizedDescriptionKey];
            
            if (verifyAppcastDataInnerError != nil) {
                [userInfo setObject:verifyAppcastDataInnerError forKey:NSUnderlyingErrorKey];
            }
            
            verifyAppcastDataFailureError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:userInfo];
            
            // If we can recover from signing validation failure for now, still hold onto failureVerifyAppcastDataError
            // because we will use it later on if there's no actual new update to report
            if (!canRecoverFromSigningValidationFailure) {
                [delegate didFailToFetchAppcastWithError:verifyAppcastDataFailureError];
                return;
            }
            
            appcastSigningValidationStatus = SPUAppcastSigningValidationStatusFailed;
        } else {
            // Feed validation passes
            if (initialFailedFeedSigningValidationDateKey != nil) {
                [hostForFailedSigningValidationDate setObject:nil forUserDefaultsKey:initialFailedFeedSigningValidationDateKey];
            }
            
            appcastSigningValidationStatus = SPUAppcastSigningValidationStatusSucceeded;
        }
    } else {
        verifiedAppcastData = downloadedAppcastData;
        appcastSigningValidationStatus = SPUAppcastSigningValidationStatusSkipped;
    }
 
    NSError *appcastError = nil;
    SUAppcast *loadedAppcast = [[SUAppcast alloc] initWithXMLData:verifiedAppcastData relativeToURL:downloadData.URL stateResolver:stateResolver signingValidationStatus:appcastSigningValidationStatus error:&appcastError];
    
    if (loadedAppcast == nil) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:SULocalizedStringFromTableInBundle(@"An error occurred while parsing the update feed.", SPARKLE_TABLE, SUSparkleBundle(), nil) forKey:NSLocalizedDescriptionKey];
        
        if (appcastError != nil) {
            [userInfo setObject:appcastError forKey:NSUnderlyingErrorKey];
        }
        
        [delegate didFailToFetchAppcastWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAppcastParseError userInfo:userInfo]];
        
        return;
    }
    
    // Now process the loaded appcast and find a suitable update item
    
    [delegate didFinishLoadingAppcast:loadedAppcast];
    
    id updater = _updater;
    if (updater != nil) {
        NSDictionary *userInfo = @{ SUUpdaterAppcastNotificationKey: loadedAppcast };
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFinishLoadingAppCastNotification object:updater userInfo:userInfo];
    }
    
    NSSet<NSString *> *allowedChannels;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(allowedChannelsForUpdater:)]) {
        allowedChannels = [updaterDelegate allowedChannelsForUpdater:updater];
        if (allowedChannels == nil) {
            SULog(SULogLevelError, @"Error: -allowedChannelsForUpdater: cannot return nil. Treating this as an empty set.");
            allowedChannels = [NSSet set];
        }
    } else {
        allowedChannels = [NSSet set];
    }
    
    SUAppcast *macOSAppcast = [SUAppcastDriver filterAppcast:loadedAppcast forMacOSAndAllowedChannels:allowedChannels];
    
    id<SUVersionComparison> applicationVersionComparator = [self versionComparator];
    
    BOOL background = _downloadDriver.inBackground;
    NSNumber *phasedUpdateGroup = background ? @([SUPhasedUpdateGroupInfo updateGroupForHost:_host]) : nil;
    
    SPUSkippedUpdate *skippedUpdate = background ? [SPUSkippedUpdate skippedUpdateForHost:_host] : nil;
    
    // First filter out min/max OS version and see if there's an update that passes
    // the minimum autoupdate version. We filter out updates that fail the minimum
    // autoupdate version test because we have a preference over minor updates that can be
    // downloaded and installed with less disturbance
    SUAppcast *passesMinimumAutoupdateAppcast = [SUAppcastDriver filterSupportedAppcast:macOSAppcast phasedUpdateGroup:phasedUpdateGroup skippedUpdate:skippedUpdate currentDate:currentDate hostVersion:_host.version versionComparator:applicationVersionComparator testMinimumSystemRequirements:YES testMinimumAutoupdateVersion:YES];
    
    SUAppcastItem *secondaryItemPassesMinimumAutoupdate = nil;
    SUAppcastItem *primaryItemPassesMinimumAutoupdate = [self retrieveBestAppcastItemFromAppcast:passesMinimumAutoupdateAppcast versionComparator:applicationVersionComparator secondaryUpdate:&secondaryItemPassesMinimumAutoupdate];
    
    // If we weren't able to find a valid update, try to find an update that
    // doesn't pass the minimum autoupdate version
    SUAppcastItem *finalPrimaryItem;
    SUAppcastItem *finalSecondaryItem = nil;
    if (![self isItemNewer:primaryItemPassesMinimumAutoupdate]) {
        SUAppcast *failsMinimumAutoupdateAppcast = [SUAppcastDriver filterSupportedAppcast:macOSAppcast phasedUpdateGroup:phasedUpdateGroup skippedUpdate:skippedUpdate currentDate:currentDate hostVersion:_host.version versionComparator:applicationVersionComparator testMinimumSystemRequirements:YES testMinimumAutoupdateVersion:NO];
        
        finalPrimaryItem = [self retrieveBestAppcastItemFromAppcast:failsMinimumAutoupdateAppcast versionComparator:applicationVersionComparator secondaryUpdate:&finalSecondaryItem];
    } else {
        finalPrimaryItem = primaryItemPassesMinimumAutoupdate;
        finalSecondaryItem = secondaryItemPassesMinimumAutoupdate;
    }
    
    // Check if we found a new suitable update
    if ([self isItemNewer:finalPrimaryItem]) {
        [delegate didFindValidUpdateWithAppcastItem:finalPrimaryItem secondaryAppcastItem:finalSecondaryItem];
        return;
    }
    
    // If we're trying to recover from a failed signing validation of the feed, show an error rather than
    // showing why there isn't a new update, which we should be cautious about
    if (appcastSigningValidationStatus == SPUAppcastSigningValidationStatusFailed && verifyAppcastDataFailureError != nil) {
        [delegate didFailToFetchAppcastWithError:verifyAppcastDataFailureError];
        return;
    }
    
    // Find the latest appcast item that we can report to the user and updater delegates
    // This may include updates that fail due to OS version requirements.
    // This excludes newer backgrounded updates that fail because they are skipped or not in current phased rollout group
    
    SUAppcast *notFoundAppcast = [SUAppcastDriver filterSupportedAppcast:macOSAppcast phasedUpdateGroup:phasedUpdateGroup skippedUpdate:skippedUpdate currentDate:currentDate hostVersion:_host.version versionComparator:applicationVersionComparator testMinimumSystemRequirements:NO testMinimumAutoupdateVersion:NO];
    
    SUAppcastItem *notFoundPrimaryItem = [self retrieveBestAppcastItemFromAppcast:notFoundAppcast versionComparator:applicationVersionComparator secondaryUpdate:nil];
    
    NSComparisonResult hostToLatestAppcastItemComparisonResult;
    if (notFoundPrimaryItem != nil) {
        hostToLatestAppcastItemComparisonResult = [applicationVersionComparator compareVersion:_host.version toVersion:notFoundPrimaryItem.versionString];
    } else {
        hostToLatestAppcastItemComparisonResult = NSOrderedSame;
    }
    
    [delegate didNotFindUpdateWithLatestAppcastItem:notFoundPrimaryItem hostToLatestAppcastItemComparisonResult:hostToLatestAppcastItemComparisonResult background:background];
}

- (void)downloadDriverDidFailToDownloadFileWithError:(nonnull NSError *)error
{
    SULog(SULogLevelError, @"Encountered download feed error: %@", error);

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred in retrieving update information. Please try again later.", SPARKLE_TABLE, SUSparkleBundle(), nil)}];
    
    if (error != nil) {
        [userInfo setObject:error forKey:NSUnderlyingErrorKey];
    }
    
    [_delegate didFailToFetchAppcastWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]];
}

- (SUAppcastItem * _Nullable)preferredUpdateForRegularAppcastItem:(SUAppcastItem * _Nullable)regularItem secondaryUpdate:(SUAppcastItem * __autoreleasing _Nullable *)secondaryUpdate SPU_OBJC_DIRECT
{
    SUAppcastItem *deltaItem = (regularItem != nil) ? [[self class] deltaUpdateFromAppcastItem:regularItem hostVersion:_host.version] : nil;
    
    BOOL supportsDeltaItem;
    if (deltaItem == nil) {
        supportsDeltaItem = NO;
    } else {
        // Delta updates are not supported when bundles are transferred over to some file systems like fat32 and exfat systems
        // This is because they do not preserve permissions completely, which we require for diff'ing.
        // We shouldn't download delta updates in cases where we can detect they aren't supported
        // More accurately we will detect if the host bundle's permission bits have been 'tainted'
        // which is more reliable than checking the underlying file system.
        // To do this, we will check the Sparkle executable's permission bits, which is produced from us
        // We will also check if the executable file or the localization files have been stripped from Sparkle.framework
        
        NSFileManager *fileManager = NSFileManager.defaultManager;
        
        NSBundle *hostBundle = _host.bundle;
        NSString *sparkleExecutablePath;
        NSString *sparkleResourcesPath;
        if ([hostBundle isEqual:NSBundle.mainBundle]) {
            NSBundle *sparkleBundle = [NSBundle bundleForClass:[self class]];
            sparkleExecutablePath = sparkleBundle.executableURL.URLByResolvingSymlinksInPath.path;
            sparkleResourcesPath = sparkleBundle.resourcePath;
        } else {
            // If we are not updating ourselves, make a good guess to the Sparkle executable location
            NSURL *frameworksURL = hostBundle.privateFrameworksURL;
            NSURL *sparkleSymlinkURL = [frameworksURL URLByAppendingPathComponent:@"Sparkle.framework/Sparkle"];
            NSString *candidateExecutablePath = sparkleSymlinkURL.URLByResolvingSymlinksInPath.path;
            
            if ([fileManager fileExistsAtPath:candidateExecutablePath]) {
                sparkleExecutablePath = candidateExecutablePath;
                sparkleResourcesPath = [candidateExecutablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"Resources"];
            } else {
                sparkleExecutablePath = nil;
                sparkleResourcesPath = nil;
            }
        }
        
        if (sparkleExecutablePath != nil) {
            NSError *attributesError = nil;
            NSDictionary<NSFileAttributeKey, id> *attributes = [fileManager attributesOfItemAtPath:sparkleExecutablePath error:&attributesError];
            
            BOOL sparkleExecutableIsOK;
            if (attributes != nil) {
                // Skip delta updates if permissions are not 0755
                NSNumber *posixPermissions = attributes[NSFilePosixPermissions];
                if (posixPermissions != nil && posixPermissions.shortValue != 0755) {
                    sparkleExecutableIsOK = NO;
                    
                    // Irregular permissions on the Sparkle executable could mean the app was transferred on a file system we don't support
                    // (which doesn't track all permissions)
                    SULog(SULogLevelDefault, @"Encountered irregular POSIX permissions 0%o for Sparkle executable, which is not 0755. Skipping delta updates..", posixPermissions.shortValue);
                } else {
                    // Test if Sparkle's executable file on disk has expected file size for applying this delta update
                    // If the file size has been reduced, the user could have stripped an architecture out
                    if (deltaItem.deltaFromSparkleExecutableSize != nil) {
                        NSNumber *fileSize = attributes[NSFileSize];
                        if (fileSize != nil && ![deltaItem.deltaFromSparkleExecutableSize isEqualToNumber:fileSize]) {
                            sparkleExecutableIsOK = NO;
                            
                            SULog(SULogLevelDefault, @"Expected file size (%llu) of Sparkle's executable does not match actual file size (%llu). Skipping delta update.", deltaItem.deltaFromSparkleExecutableSize.unsignedLongLongValue, fileSize.unsignedLongLongValue);
                        } else {
                            sparkleExecutableIsOK = YES;
                        }
                    } else {
                        sparkleExecutableIsOK = YES;
                    }
                }
            } else {
                sparkleExecutableIsOK = YES;
                
                SULog(SULogLevelError, @"Error: Failed to retrieve attributes from Sparkle executable: %@", attributesError.localizedDescription);
            }
            
            // Test if Sparkle's expected localization files on disk are still present for applying this delta update
            // If there are missing localization files, the user could have stripped them out
            // No need to test this though if !sparkleExecutableIsOK
            BOOL sparkleResourcesAreOK;
            if (sparkleExecutableIsOK && sparkleResourcesPath != nil && deltaItem.deltaFromSparkleLocales != nil) {
                BOOL foundAllExpectedLocales = YES;
                for (NSString *locale in deltaItem.deltaFromSparkleLocales) {
                    NSString *localeProjectPath = [[sparkleResourcesPath stringByAppendingPathComponent:locale] stringByAppendingPathExtension:@"lproj"];
                    if (![fileManager fileExistsAtPath:localeProjectPath]) {
                        foundAllExpectedLocales = NO;
                        
                        SULog(SULogLevelDefault, @"Expected project locale (%@) is missing in Sparkle.framework. Skipping delta update.", locale);
                        break;
                    }
                }
                
                sparkleResourcesAreOK = foundAllExpectedLocales;
            } else {
                sparkleResourcesAreOK = YES;
            }
            
            supportsDeltaItem = sparkleExecutableIsOK && sparkleResourcesAreOK;
        } else {
            supportsDeltaItem = YES;
            
            SULog(SULogLevelError, @"Error: Failed to unexpectably retrieve Sparkle executable URL from %@", hostBundle.bundlePath);
        }
    }
    
    if (supportsDeltaItem) {
        if (secondaryUpdate != NULL) {
            *secondaryUpdate = regularItem;
        }
        return deltaItem;
    } else {
        if (secondaryUpdate != NULL) {
            *secondaryUpdate = nil;
        }
        return regularItem;
    }
}

- (SUAppcastItem *)retrieveBestAppcastItemFromAppcast:(SUAppcast *)appcast versionComparator:(id<SUVersionComparison>)versionComparator secondaryUpdate:(SUAppcastItem * __autoreleasing _Nullable *)secondaryAppcastItem SPU_OBJC_DIRECT
{
    // Find the best valid update in the appcast by asking the delegate
    // Don't ask the delegate if the appcast has no items though
    id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    id updater = _updater;
    SUAppcastItem *regularItemFromDelegate;
    BOOL delegateOptedOutOfSelection;
    if (appcast.items.count > 0 && updater != nil && [updaterDelegate respondsToSelector:@selector((bestValidUpdateInAppcast:forUpdater:))]) {
        SUAppcastItem *candidateItem = [updaterDelegate bestValidUpdateInAppcast:appcast forUpdater:updater];
        
        if (candidateItem == SUAppcastItem.emptyAppcastItem) {
            regularItemFromDelegate = nil;
            delegateOptedOutOfSelection = YES;
        } else if (candidateItem == nil) {
            regularItemFromDelegate = nil;
            delegateOptedOutOfSelection = NO;
        } else {
            if (candidateItem.deltaUpdate) {
                // Client would have to go out of their way to examine the .deltaUpdates to return one
                // We need them to give us a regular update item back instead..
                SULog(SULogLevelError, @"Error: -bestValidUpdateInAppcast:forUpdater: cannot return a delta update item");
                regularItemFromDelegate = nil;
            } else {
                regularItemFromDelegate = candidateItem;
            }
            
            delegateOptedOutOfSelection = NO;
        }
    } else {
        regularItemFromDelegate = nil;
        delegateOptedOutOfSelection = NO;
    }
    
    // Take care of finding best appcast item ourselves if delegate does not
    SUAppcastItem *regularItem;
    if (regularItemFromDelegate == nil && !delegateOptedOutOfSelection) {
        regularItem = [SUAppcastDriver bestItemFromAppcastItems:appcast.items comparator:versionComparator];
    } else {
        regularItem = regularItemFromDelegate;
    }
    
    // Retrieve the preferred primary and secondary update items
    // In the case of a delta update, the preferred primary item will be the delta update,
    // and the secondary item will be the regular update.
    return [self preferredUpdateForRegularAppcastItem:regularItem secondaryUpdate:secondaryAppcastItem];
}

// Note: This method is used by unit tests
+ (SUAppcast *)filterAppcast:(SUAppcast *)appcast forMacOSAndAllowedChannels:(NSSet<NSString *> *)allowedChannels
#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT
#endif
{
    return [appcast copyByFilteringItems:^(SUAppcastItem *item) {
        // We will never care about other OS's
        BOOL macOSUpdate = [item isMacOsUpdate];
        if (!macOSUpdate) {
            return NO;
        }
        
        // Delta updates cannot be top-level entries
        BOOL isDeltaUpdate = [item isDeltaUpdate];
        if (isDeltaUpdate) {
            return NO;
        }
        
        // We should never be interested in the update if it doesn't pass the minimum update version
        BOOL passesUpdateVersion = item.minimumUpdateVersionIsOK;
        if (!passesUpdateVersion) {
            return NO;
        }
        
        NSString *channel = item.channel;
        if (channel == nil) {
            // Item is on the default channel
            return YES;
        }
        
        return [allowedChannels containsObject:channel];
    }];
}

// Note: This method is used by unit tests
+ (SUAppcast *)filterSupportedAppcast:(SUAppcast *)appcast phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup skippedUpdate:(SPUSkippedUpdate * _Nullable)skippedUpdate currentDate:(NSDate *)currentDate hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator testMinimumSystemRequirements:(BOOL)testMinimumSystemRequirements testMinimumAutoupdateVersion:(BOOL)testMinimumAutoupdateVersion
#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT
#endif
{
    BOOL hostPassesSkippedMajorVersion = [SPUAppcastItemStateResolver isMinimumAutoupdateVersionOK:skippedUpdate.majorVersion hostVersion:hostVersion versionComparator:versionComparator];
    
    return [appcast copyByFilteringItems:^(SUAppcastItem *item) {
        BOOL passesOSVersion = (!testMinimumSystemRequirements || (item.minimumOperatingSystemVersionIsOK && item.maximumOperatingSystemVersionIsOK));
        
        BOOL passesHardwareRequirements = (!testMinimumSystemRequirements || item.arm64HardwareRequirementIsOK);
        
        BOOL passesPhasedRollout = [self itemIsReadyForPhasedRollout:item phasedUpdateGroup:phasedUpdateGroup currentDate:currentDate hostVersion:hostVersion versionComparator:versionComparator];
        
        BOOL passesMinimumAutoupdateVersion = (!testMinimumAutoupdateVersion || !item.majorUpgrade);
        
        BOOL passesSkippedUpdates = (versionComparator == nil || hostVersion == nil || ![self item:item containsSkippedUpdate:skippedUpdate hostPassesSkippedMajorVersion:hostPassesSkippedMajorVersion versionComparator:versionComparator]);
        
        return (BOOL)(passesOSVersion && passesHardwareRequirements && passesPhasedRollout && passesMinimumAutoupdateVersion && passesSkippedUpdates);
    }];
}

+ (SUAppcastItem * _Nullable)deltaUpdateFromAppcastItem:(SUAppcastItem *)appcastItem hostVersion:(NSString *)hostVersion
{
    return appcastItem.deltaUpdates[hostVersion];
}

+ (SUAppcastItem * _Nullable)bestItemFromAppcastItems:(NSArray *)appcastItems comparator:(id<SUVersionComparison>)comparator
{
    SUAppcastItem *item = nil;
    for(SUAppcastItem *candidate in appcastItems) {
        // Note if two items are equal, we must select the first matching one
        if (!item || [comparator compareVersion:item.versionString toVersion:candidate.versionString] == NSOrderedAscending) {
            item = candidate;
        }
    }
    return item;
}

// Note: this method is used by unit tests
// This method should not do *any* filtering, only version comparing
+ (SUAppcastItem *)bestItemFromAppcastItems:(NSArray *)appcastItems getDeltaItem:(SUAppcastItem * __autoreleasing *)deltaItem withHostVersion:(NSString *)hostVersion comparator:(id<SUVersionComparison>)comparator
#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT
#endif
{
    SUAppcastItem *item = [self bestItemFromAppcastItems:appcastItems comparator:comparator];
    if (item != nil && deltaItem != NULL) {
        *deltaItem = [self deltaUpdateFromAppcastItem:item hostVersion:hostVersion];
    }
    return item;
}

- (id<SUVersionComparison>)versionComparator SPU_OBJC_DIRECT
{
    id<SUVersionComparison> comparator = nil;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // Give the delegate a chance to provide a custom version comparator
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    if ([updaterDelegate respondsToSelector:@selector((versionComparatorForUpdater:))]) {
        id updater = _updater;
        if (updater != nil) {
            comparator = [updaterDelegate versionComparatorForUpdater:updater];
        }
    }
#pragma clang diagnostic pop
    
    // If we don't get a comparator from the delegate, use the default comparator
    if (comparator == nil) {
        comparator = [SUStandardVersionComparator defaultComparator];
    }
    
    return comparator;
}

- (BOOL)isItemNewer:(SUAppcastItem *)ui SPU_OBJC_DIRECT
{
    return ui != nil && [[self versionComparator] compareVersion:_host.version toVersion:ui.versionString] == NSOrderedAscending;
}

+ (BOOL)item:(SUAppcastItem *)ui containsSkippedUpdate:(SPUSkippedUpdate * _Nullable)skippedUpdate hostPassesSkippedMajorVersion:(BOOL)hostPassesSkippedMajorVersion versionComparator:(id<SUVersionComparison>)versionComparator SPU_OBJC_DIRECT
{
    NSString *skippedMajorVersion = skippedUpdate.majorVersion;
    NSString *skippedMajorSubreleaseVersion = skippedUpdate.majorSubreleaseVersion;
    
    if (!hostPassesSkippedMajorVersion && skippedMajorVersion != nil && ui.minimumAutoupdateVersion != nil && [versionComparator compareVersion:skippedMajorVersion toVersion:(NSString * _Nonnull)ui.minimumAutoupdateVersion] != NSOrderedAscending && (ui.ignoreSkippedUpgradesBelowVersion == nil || (skippedMajorSubreleaseVersion != nil && [versionComparator compareVersion:skippedMajorSubreleaseVersion toVersion:(NSString * _Nonnull)ui.ignoreSkippedUpgradesBelowVersion] != NSOrderedAscending))) {
        // If skipped major version is >= than the item's minimumAutoupdateVersion, we can skip the item.
        // But if there is an ignoreSkippedUpgradesBelowVersion, we can only skip the item if the last skipped subrelease
        // version is >= than that version provided by the item
        return YES;
    }
    
    NSString *skippedMinorVersion = skippedUpdate.minorVersion;
    
    if (skippedMinorVersion != nil && [versionComparator compareVersion:skippedMinorVersion toVersion:ui.versionString] != NSOrderedAscending) {
        // Item is on a less or equal version than a minor version we've skipped
        // So we skip this item
        return YES;
    }
    
    return NO;
}

+ (BOOL)itemIsReadyForPhasedRollout:(SUAppcastItem *)ui phasedUpdateGroup:(NSNumber * _Nullable)phasedUpdateGroup currentDate:(NSDate *)currentDate hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator SPU_OBJC_DIRECT
{
    if (phasedUpdateGroup == nil || ui.criticalUpdate) {
        return YES;
    }
    
    NSNumber *phasedRolloutIntervalObject = [ui phasedRolloutInterval];
    if (phasedRolloutIntervalObject == nil) {
        return YES;
    }
    
    NSDate* itemReleaseDate = ui.date;
    if (itemReleaseDate == nil) {
        return YES;
    }
    
    NSTimeInterval timeSinceRelease = [currentDate timeIntervalSinceDate:itemReleaseDate];
    
    NSTimeInterval phasedRolloutInterval = [phasedRolloutIntervalObject doubleValue];
    NSTimeInterval timeToWaitForGroup = phasedRolloutInterval * (NSTimeInterval)(phasedUpdateGroup.unsignedIntegerValue);
    
    if (timeSinceRelease >= timeToWaitForGroup) {
        return YES;
    }
    
    return NO;
}

- (void)cleanup:(void (^)(void))completionHandler
{
    if (_downloadDriver == nil) {
        completionHandler();
    } else {
        [_downloadDriver cleanup:completionHandler];
    }
}

@end
