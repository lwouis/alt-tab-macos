//
//  SPUStandardVersionDisplay.m
//  Sparkle
//
//  Created on 2/18/23.
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import "SPUStandardVersionDisplay.h"
#import "SUAppcastItem.h"


#include "AppKitPrevention.h"

@implementation SPUStandardVersionDisplay

+ (instancetype)standardVersionDisplay
{
    static SPUStandardVersionDisplay *versionDisplay = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        versionDisplay = [[SPUStandardVersionDisplay alloc] init];
    });
    return versionDisplay;
}

- (NSString *)formatUpdateDisplayVersionFromUpdate:(SUAppcastItem *)update andBundleDisplayVersion:(NSString * _Nonnull __autoreleasing * _Nonnull)inOutBundleDisplayVersion withBundleVersion:(NSString *)bundleVersion
{
    NSString *outUpdateDisplayVersion;
    NSString *outBundleDisplayVersion;
    
    NSString *updateDisplayVersion = update.displayVersionString;
    NSString *bundleDisplayVersion = *inOutBundleDisplayVersion;
    
    NSString *updateVersion = update.versionString;
    
    // If the display versions are the same, then append the internal versions to differentiate them
    if ([updateDisplayVersion isEqualToString:bundleDisplayVersion]) {
        outUpdateDisplayVersion = [updateDisplayVersion stringByAppendingFormat:@" (%@)", updateVersion];
        outBundleDisplayVersion = [bundleDisplayVersion stringByAppendingFormat:@" (%@)", bundleVersion];
    } else {
        outUpdateDisplayVersion = updateDisplayVersion;
        outBundleDisplayVersion = bundleDisplayVersion;
    }
    
    *inOutBundleDisplayVersion = outBundleDisplayVersion;
    
    return outUpdateDisplayVersion;
}

@end
