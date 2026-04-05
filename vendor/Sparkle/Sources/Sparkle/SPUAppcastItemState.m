//
//  SPUAppcastItemState.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/31/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUAppcastItemState.h"


#include "AppKitPrevention.h"

#define SPUAppcastItemStateMajorUpgradeKey @"SPUAppcastItemStateMajorUpgrade"
#define SPUAppcastItemStateCriticalUpdateKey @"SPUAppcastItemStateCriticalUpdate"
#define SPUAppcastItemStateInformationalUpdateKey @"SPUAppcastItemStateInformationalUpdate"
#define SPUAppcastItemStateUpdateMinimumVersionIsOKKey @"SPUAppcastItemStateMinimumUpdateVersionIsOK"
#define SPUAppcastItemStateMinimumOperatingSystemVersionIsOKKey @"SPUAppcastItemStateMinimumOperatingSystemVersionIsOK"
#define SPUAppcastItemStateMaximumOperatingSystemVersionIsOKKey @"SPUAppcastItemStateMaximumOperatingSystemVersionIsOK"
#define SPUAppcastItemStateArm64HardwareRequirementIsOKKey @"SPUAppcastItemStateArm64HardwareRequirementIsOK"

@interface SPUAppcastItemState () <NSSecureCoding>
@end

@implementation SPUAppcastItemState

@synthesize majorUpgrade = _majorUpgrade;
@synthesize criticalUpdate = _criticalUpdate;
@synthesize informationalUpdate = _informationalUpdate;
@synthesize minimumUpdateVersionIsOK = _minimumUpdateVersionIsOK;
@synthesize minimumOperatingSystemVersionIsOK = _minimumOperatingSystemVersionIsOK;
@synthesize maximumOperatingSystemVersionIsOK = _maximumOperatingSystemVersionIsOK;
@synthesize arm64HardwareRequirementIsOK = _arm64HardwareRequirementIsOK;

- (instancetype)initWithMajorUpgrade:(BOOL)majorUpgrade criticalUpdate:(BOOL)criticalUpdate informationalUpdate:(BOOL)informationalUpdate minimumUpdateVersionIsOK:(BOOL)minimumUpdateVersionIsOK minimumOperatingSystemVersionIsOK:(BOOL)minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:(BOOL)maximumOperatingSystemVersionIsOK arm64HardwareRequirementIsOK:(BOOL)arm64HardwareRequirementIsOK
{
    self = [super init];
    if (self != nil) {
        _majorUpgrade = majorUpgrade;
        _criticalUpdate = criticalUpdate;
        _informationalUpdate = informationalUpdate;
        _minimumUpdateVersionIsOK = minimumUpdateVersionIsOK;
        _minimumOperatingSystemVersionIsOK = minimumOperatingSystemVersionIsOK;
        _maximumOperatingSystemVersionIsOK = maximumOperatingSystemVersionIsOK;
        _arm64HardwareRequirementIsOK = arm64HardwareRequirementIsOK;
    }
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeBool:_majorUpgrade forKey:SPUAppcastItemStateMajorUpgradeKey];
    [encoder encodeBool:_criticalUpdate forKey:SPUAppcastItemStateCriticalUpdateKey];
    [encoder encodeBool:_informationalUpdate forKey:SPUAppcastItemStateInformationalUpdateKey];
    [encoder encodeBool:_minimumUpdateVersionIsOK forKey:SPUAppcastItemStateUpdateMinimumVersionIsOKKey];
    [encoder encodeBool:_minimumOperatingSystemVersionIsOK forKey:SPUAppcastItemStateMinimumOperatingSystemVersionIsOKKey];
    [encoder encodeBool:_maximumOperatingSystemVersionIsOK forKey:SPUAppcastItemStateMaximumOperatingSystemVersionIsOKKey];
    [encoder encodeBool:_arm64HardwareRequirementIsOK forKey:SPUAppcastItemStateArm64HardwareRequirementIsOKKey];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    BOOL majorUpgrade = [decoder decodeBoolForKey:SPUAppcastItemStateMajorUpgradeKey];
    BOOL criticalUpdate = [decoder decodeBoolForKey:SPUAppcastItemStateCriticalUpdateKey];
    BOOL informationalUpdate = [decoder decodeBoolForKey:SPUAppcastItemStateInformationalUpdateKey];
    BOOL minimumUpdateVersionIsOK = [decoder decodeBoolForKey:SPUAppcastItemStateUpdateMinimumVersionIsOKKey];
    BOOL minimumOperatingSystemVersionIsOK = [decoder decodeBoolForKey:SPUAppcastItemStateMinimumOperatingSystemVersionIsOKKey];
    BOOL maximumOperatingSystemVersionIsOK = [decoder decodeBoolForKey:SPUAppcastItemStateMaximumOperatingSystemVersionIsOKKey];
    BOOL arm64HardwareRequirementIsOK = [decoder decodeBoolForKey:SPUAppcastItemStateArm64HardwareRequirementIsOKKey];
    
    return [self initWithMajorUpgrade:majorUpgrade criticalUpdate:criticalUpdate informationalUpdate:informationalUpdate minimumUpdateVersionIsOK:minimumUpdateVersionIsOK minimumOperatingSystemVersionIsOK:minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:maximumOperatingSystemVersionIsOK arm64HardwareRequirementIsOK:arm64HardwareRequirementIsOK];
}

@end
