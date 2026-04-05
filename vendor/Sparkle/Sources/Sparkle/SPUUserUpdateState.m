//
//  SPUUserUpdateState.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/9/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUUserUpdateState.h"
#import "SPUUserUpdateState+Private.h"


#include "AppKitPrevention.h"

#define SPUUserUpdateStateStageKey @"SPUUserUpdateStateStage"
#define SPUUserUpdateStateUserInitiatedKey @"SPUUserUpdateStateUserInitiated"
#define SPUUserUpdateStateMajorUpgradeKey @"SPUUserUpdateStateMajorUpgrade"
#define SPUUserUpdateStateCriticalUpdateKey @"SPUUserUpdateStateCriticalUpdate"

@implementation SPUUserUpdateState

@synthesize stage = _stage;
@synthesize userInitiated = _userInitiated;

- (instancetype)initWithStage:(SPUUserUpdateStage)stage userInitiated:(BOOL)userInitiated
{
    self = [super init];
    if (self != nil) {
        _stage = stage;
        _userInitiated = userInitiated;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:_stage forKey:SPUUserUpdateStateStageKey];
    [encoder encodeBool:_userInitiated forKey:SPUUserUpdateStateUserInitiatedKey];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    SPUUserUpdateStage stage = (SPUUserUpdateStage)[decoder decodeIntegerForKey:SPUUserUpdateStateStageKey];
    BOOL userInitiated = [decoder decodeBoolForKey:SPUUserUpdateStateUserInitiatedKey];
    
    return [self initWithStage:stage userInitiated:userInitiated];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
