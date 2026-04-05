//
//  SPUAppcastItemStateResolver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/31/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUAppcastItemStateResolver.h"
#import "SPUAppcastItemStateResolver+Private.h"
#import "SPUAppcastItemState.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUConstants.h"
#import "SUOperatingSystem.h"
#import "SULog.h"

#import <TargetConditionals.h>
#import <sys/types.h>
#import <sys/sysctl.h>

#include "AppKitPrevention.h"

@implementation SPUAppcastItemStateResolver
{
    NSString *_hostVersion;
    id<SUVersionComparison> _applicationVersionComparator;
    SUStandardVersionComparator *_standardVersionComparator;
}

- (instancetype)initWithHostVersion:(NSString *)hostVersion applicationVersionComparator:(id<SUVersionComparison>)applicationVersionComparator standardVersionComparator:(SUStandardVersionComparator *)standardVersionComparator
{
    self = [super init];
    if (self != nil) {
        _hostVersion = [hostVersion copy];
        _applicationVersionComparator = applicationVersionComparator;
        _standardVersionComparator = standardVersionComparator;
    }
    return self;
}

- (BOOL)isMinimumUpdateVersionOK:(NSString * _Nullable)minimumUpdateVersion SPU_OBJC_DIRECT
{
    NSString *hostVersion = _hostVersion;
    
    BOOL minimumVersionOK = YES;
    if (minimumUpdateVersion != nil && ![minimumUpdateVersion isEqualToString:@""]) {
        minimumVersionOK = [_applicationVersionComparator compareVersion:(NSString * _Nonnull)minimumUpdateVersion toVersion:hostVersion] != NSOrderedDescending;
    }
    return minimumVersionOK;
}

- (BOOL)isMinimumOperatingSystemVersionOK:(NSString * _Nullable)minimumSystemVersion SPU_OBJC_DIRECT
{
    BOOL minimumVersionOK = YES;
    if (minimumSystemVersion != nil && ![minimumSystemVersion isEqualToString:@""]) {
        minimumVersionOK = [_standardVersionComparator compareVersion:(NSString * _Nonnull)minimumSystemVersion toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedDescending;
    }
    return minimumVersionOK;
}

- (BOOL)isMaximumOperatingSystemVersionOK:(NSString * _Nullable)maximumSystemVersion SPU_OBJC_DIRECT
{
    BOOL maximumVersionOK = YES;
    if (maximumSystemVersion != nil && ![maximumSystemVersion isEqualToString:@""]) {
        maximumVersionOK = [_standardVersionComparator compareVersion:(NSString * _Nonnull)maximumSystemVersion toVersion:[SUOperatingSystem systemVersionString]] != NSOrderedAscending;
    }
    return maximumVersionOK;
}

+ (BOOL)isMinimumAutoupdateVersionOK:(NSString * _Nullable)minimumAutoupdateVersion hostVersion:(NSString *)hostVersion versionComparator:(id<SUVersionComparison>)versionComparator
 {
     return (minimumAutoupdateVersion.length == 0 || ([versionComparator compareVersion:hostVersion toVersion:(NSString * _Nonnull)minimumAutoupdateVersion] != NSOrderedAscending));
 }

- (BOOL)isMinimumAutoupdateVersionOK:(NSString * _Nullable)minimumAutoupdateVersion SPU_OBJC_DIRECT
 {
     return [[self class] isMinimumAutoupdateVersionOK:minimumAutoupdateVersion hostVersion:_hostVersion versionComparator:_applicationVersionComparator];
 }

- (BOOL)isCriticalUpdateWithCriticalUpdateDictionary:(NSDictionary * _Nullable)criticalUpdateDictionary SPU_OBJC_DIRECT
{
    // Check if any critical update info is provided
    if (criticalUpdateDictionary == nil) {
        return NO;
    }
    
    // If no critical version is supplied, then it is critical
    NSString *criticalVersion = criticalUpdateDictionary[SUAppcastAttributeVersion];
    if (criticalVersion == nil || ![criticalVersion isKindOfClass:[NSString class]]) {
        return YES;
    }
    
    // Update is only critical when coming from previous versions
    return ([_applicationVersionComparator compareVersion:_hostVersion toVersion:criticalVersion] == NSOrderedAscending);
}

- (BOOL)isInformationalUpdateWithInformationalUpdateVersions:(NSSet<NSString *> * _Nullable)informationalUpdateVersions SPU_OBJC_DIRECT
{
    if (informationalUpdateVersions == nil) {
        return NO;
    }
    
    // Informational only update regardless of version the app is updating from
    if (informationalUpdateVersions.count == 0) {
        return YES;
    }
    
    NSString *hostVersion = _hostVersion;
    
    // Informational update only for a set of host versions we're updating from
    if ([informationalUpdateVersions containsObject:hostVersion]) {
        return YES;
    }
    
    // If an informational update version has a '<' prefix, this is an informational update if
    // hostVersion < this info update version
    for (NSString *informationalUpdateVersion in informationalUpdateVersions) {
        if ([informationalUpdateVersion hasPrefix:@"<"] && [_applicationVersionComparator compareVersion:hostVersion toVersion:[informationalUpdateVersion substringFromIndex:1]] == NSOrderedAscending) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isArm64HardwareRequirementOK:(NSSet<NSString *> *)hardwareRequirements minimumSystemVersion:(NSString *_Nullable )minimumSystemVersion SPU_OBJC_DIRECT
{
#if TARGET_CPU_X86_64
    // macOS 27+ will no longer support Intel Macs
    BOOL hasARM64Requirement;
    if (minimumSystemVersion.length > 0 && [_standardVersionComparator compareVersion:(NSString * _Nonnull)minimumSystemVersion toVersion:@"27.0"] != NSOrderedAscending) {
        hasARM64Requirement = YES;
    } else {
        hasARM64Requirement = [hardwareRequirements containsObject:SUAppcastElementHardwareRequirementARM64];
    }
    
    if (!hasARM64Requirement) {
        return YES;
    }
    
    // If the process is run under Rosetta, then the hardware is compatible
    // https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
    int translatedResult = 0;
    size_t translatedResultSize = sizeof(translatedResult);
    if (sysctlbyname("sysctl.proc_translated", &translatedResult, &translatedResultSize, NULL, 0) == -1) {
        if (errno == ENOENT) {
            // Native x86_64 process
            return NO;
        }
        
        // An error occured
        SULog(SULogLevelError, @"Error: failed to detect if process is running under rosetta with error: %d", errno);
        return YES;
    }
    
    return (translatedResult == 1);
#else
    return YES;
#endif
}

- (SPUAppcastItemState *)resolveStateWithInformationalUpdateVersions:(NSSet<NSString *> * _Nullable)informationalUpdateVersions minimumUpdateVersion:(NSString * _Nullable)minimumUpdateVersion minimumOperatingSystemVersion:(NSString * _Nullable)minimumOperatingSystemVersion maximumOperatingSystemVersion:(NSString * _Nullable)maximumOperatingSystemVersion minimumAutoupdateVersion:(NSString * _Nullable)minimumAutoupdateVersion criticalUpdateDictionary:(NSDictionary * _Nullable)criticalUpdateDictionary hardwareRequirements:(NSSet<NSString *> *)hardwareRequirements
{
    BOOL informationalUpdate = [self isInformationalUpdateWithInformationalUpdateVersions:informationalUpdateVersions];
    
    BOOL minimumUpdateVersionIsOK = [self isMinimumUpdateVersionOK:minimumUpdateVersion];
    
    BOOL minimumOperatingSystemVersionIsOK = [self isMinimumOperatingSystemVersionOK:minimumOperatingSystemVersion];
    
    BOOL maximumOperatingSystemVersionIsOK = [self isMaximumOperatingSystemVersionOK:maximumOperatingSystemVersion];
    
    BOOL majorUpgrade = ![self isMinimumAutoupdateVersionOK:minimumAutoupdateVersion];
    
    BOOL criticalUpdate = [self isCriticalUpdateWithCriticalUpdateDictionary:criticalUpdateDictionary];
    
    BOOL arm64HardwareRequirementIsOK = [self isArm64HardwareRequirementOK:hardwareRequirements minimumSystemVersion:minimumOperatingSystemVersion];
    
    return [[SPUAppcastItemState alloc] initWithMajorUpgrade:majorUpgrade criticalUpdate:criticalUpdate informationalUpdate:informationalUpdate minimumUpdateVersionIsOK:minimumUpdateVersionIsOK minimumOperatingSystemVersionIsOK:minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:maximumOperatingSystemVersionIsOK arm64HardwareRequirementIsOK:arm64HardwareRequirementIsOK];
}

@end
