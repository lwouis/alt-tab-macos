//
//  SPUInformationalUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 1/8/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SPUInformationalUpdate.h"


#include "AppKitPrevention.h"

@implementation SPUInformationalUpdate

// If we ever enable auto-synthesize in the future, we'll still need this synthesize
// because the property is declared in a protocol
@synthesize updateItem = _updateItem;
@synthesize secondaryUpdateItem = _secondaryUpdateItem;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _secondaryUpdateItem = secondaryUpdateItem;
    }
    return self;
}

@end
