//
//  SPUUpdaterCycle.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterCycle.h"


#include "AppKitPrevention.h"

@implementation SPUUpdaterCycle
{
    __weak id<SPUUpdaterCycleDelegate> _delegate;
}

- (instancetype)initWithDelegate:(id<SPUUpdaterCycleDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)resetUpdateCycle
{
    [_delegate resetUpdateCycle];
}

- (void)resetUpdateCycleAfterDelay
{
    [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (void)cancelNextUpdateCycle
{
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
}

@end
