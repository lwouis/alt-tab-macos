//
//  SPUNoUpdateFoundInfo.m
//  Sparkle
//
//  Created on 2/18/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import "SPUNoUpdateFoundInfo.h"
#import "SUAppcastItem.h"
#import "SUHost.h"
#import "SULocalizations.h"
#import "SUlog.h"


#include "AppKitPrevention.h"

NSString *SPUNoUpdateFoundRecoverySuggestion(SPUNoUpdateFoundReason reason, SUAppcastItem *latestAppcastItem, SUHost *host, id<SUVersionDisplay> versionDisplayer, NSBundle *sparkleBundle)
{
#if !SPARKLE_COPY_LOCALIZATIONS
    (void)sparkleBundle;
#endif
    
    NSString *hostDisplayVersion;
    NSString *latestAppcastItemDisplayVersion;
    
    switch (reason) {
        case SPUNoUpdateFoundReasonUnknown:
        case SPUNoUpdateFoundReasonOnLatestVersion:
            if ([versionDisplayer respondsToSelector:@selector(formatBundleDisplayVersion:withBundleVersion:matchingUpdate:)]) {
                hostDisplayVersion = [versionDisplayer formatBundleDisplayVersion:host.displayVersion withBundleVersion:host.version matchingUpdate:latestAppcastItem];
            } else {
                hostDisplayVersion = host.displayVersion;
            }
            
            // This is not later used
            latestAppcastItemDisplayVersion = nil;
            break;
        case SPUNoUpdateFoundReasonOnNewerThanLatestVersion:
        case SPUNoUpdateFoundReasonSystemIsTooOld:
        case SPUNoUpdateFoundReasonSystemIsTooNew:
        case SPUNoUpdateFoundReasonHardwareDoesNotSupportARM64:
            assert(latestAppcastItem != nil);
            
            hostDisplayVersion = host.displayVersion;
            
            if ([versionDisplayer respondsToSelector:@selector(formatUpdateDisplayVersionFromUpdate:andBundleDisplayVersion:withBundleVersion:)]) {
                latestAppcastItemDisplayVersion = [versionDisplayer formatUpdateDisplayVersionFromUpdate:latestAppcastItem andBundleDisplayVersion:&hostDisplayVersion withBundleVersion:host.version];
            } else {
                // Legacy -formatVersion:andVersion: was never supported for this path so we don't need to call it
                latestAppcastItemDisplayVersion = latestAppcastItem.displayVersionString;
            }
            
            break;
    }
    
    NSString *recoverySuggestion;
    switch (reason) {
        case SPUNoUpdateFoundReasonUnknown:
        case SPUNoUpdateFoundReasonOnLatestVersion:
            recoverySuggestion = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is currently the newest version available.", SPARKLE_TABLE, sparkleBundle, nil), host.name, hostDisplayVersion];
            break;
        case SPUNoUpdateFoundReasonOnNewerThanLatestVersion:
            recoverySuggestion = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is currently the newest version available.\n(You are currently running version %@.)", SPARKLE_TABLE, sparkleBundle, nil), host.name, latestAppcastItemDisplayVersion, hostDisplayVersion];
            break;
        case SPUNoUpdateFoundReasonSystemIsTooOld:
            recoverySuggestion = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ is available but your macOS version is too old to install it. At least macOS %3$@ is required.", SPARKLE_TABLE, sparkleBundle, nil), host.name, latestAppcastItemDisplayVersion, latestAppcastItem.minimumSystemVersion];
            break;
        case SPUNoUpdateFoundReasonSystemIsTooNew:
            recoverySuggestion = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ is available but your macOS version is too new for this update. This update only supports up to macOS %3$@.", SPARKLE_TABLE, sparkleBundle, nil), host.name, latestAppcastItemDisplayVersion, latestAppcastItem.maximumSystemVersion];
            break;
        case SPUNoUpdateFoundReasonHardwareDoesNotSupportARM64:
            recoverySuggestion = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ is available but this update requires a new Apple silicon Mac.", SPARKLE_TABLE, sparkleBundle, nil), host.name, latestAppcastItemDisplayVersion];
            break;
    }
    return recoverySuggestion;
}
