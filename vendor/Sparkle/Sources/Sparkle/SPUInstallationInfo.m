//
//  SPUInstallationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallationInfo.h"
#import "SUAppcastItem.h"


#include "AppKitPrevention.h"

static NSString *SUAppcastItemKey = @"SUAppcastItem";
static NSString *SUCanSilentlyInstallKey = @"SUCanSilentlyInstall";
static NSString *SUSystemDomainKey = @"SUSystemDomain";

@implementation SPUInstallationInfo

@synthesize appcastItem = _appcastItem;
@synthesize systemDomain = _systemDomain;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem systemDomain:(BOOL)systemDomain
{
    self = [super init];
    if (self != nil) {
        _appcastItem = appcastItem;
        _systemDomain = systemDomain;
    }
    return self;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem
{
    return [self initWithAppcastItem:appcastItem systemDomain:NO];
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    SUAppcastItem *appcastItem = [decoder decodeObjectOfClass:[SUAppcastItem class] forKey:SUAppcastItemKey];
    if (appcastItem == nil) {
        return nil;
    }
    
    BOOL systemDomain = [decoder decodeBoolForKey:SUSystemDomainKey];
    return [self initWithAppcastItem:appcastItem systemDomain:systemDomain];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_appcastItem forKey:SUAppcastItemKey];
    [coder encodeBool:_systemDomain forKey:SUSystemDomainKey];
    
    // Installation types can always be silently installed for newer versions of Sparkle
    // Still encode this key to maintain backwards compatibility with older Sparkle clients
    [coder encodeBool:YES forKey:SUCanSilentlyInstallKey];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
