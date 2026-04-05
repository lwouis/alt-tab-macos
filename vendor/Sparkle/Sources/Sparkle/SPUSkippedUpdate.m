//
//  SPUSkippedUpdate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/8/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUSkippedUpdate.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUAppcastItem.h"


#include "AppKitPrevention.h"

@implementation SPUSkippedUpdate

@synthesize minorVersion = _minorVersion;
@synthesize majorVersion = _majorVersion;
@synthesize majorSubreleaseVersion = _majorSubreleaseVersion;

- (instancetype)initWithMinorVersion:(nullable NSString *)minorVersion majorVersion:(nullable NSString *)majorVersion majorSubreleaseVersion:(nullable NSString *)majorSubreleaseVersion
{
    self = [super init];
    if (self != nil) {
        _minorVersion = [minorVersion copy];
        _majorVersion = [majorVersion copy];
        _majorSubreleaseVersion = [majorSubreleaseVersion copy];
        
        assert(_minorVersion != nil || _majorVersion != nil);
    }
    return self;
}

+ (nullable SPUSkippedUpdate *)skippedUpdateForHost:(SUHost *)host
{
    NSString *minorVersion = [host objectForUserDefaultsKey:SUSkippedMinorVersionKey ofClass:NSString.class];
    NSString *majorVersion = [host objectForUserDefaultsKey:SUSkippedMajorVersionKey ofClass:NSString.class];
    NSString *majorSubreleaseVersion = [host objectForUserDefaultsKey:SUSkippedMajorSubreleaseVersionKey ofClass:NSString.class];
    
    if (minorVersion != nil || majorVersion != nil) {
        return [[SPUSkippedUpdate alloc] initWithMinorVersion:minorVersion majorVersion:majorVersion majorSubreleaseVersion:majorSubreleaseVersion];
    } else {
        return nil;
    }
}

+ (void)clearSkippedUpdateForHost:(SUHost *)host
{
    [host setObject:nil forUserDefaultsKey:SUSkippedMinorVersionKey];
    [host setObject:nil forUserDefaultsKey:SUSkippedMajorVersionKey];
    [host setObject:nil forUserDefaultsKey:SUSkippedMajorSubreleaseVersionKey];
}

+ (void)skipUpdate:(SUAppcastItem *)updateItem host:(SUHost *)host
{
    NSString *version = updateItem.versionString;
    
    if (updateItem.majorUpgrade) {
        NSString *majorVersion = updateItem.minimumAutoupdateVersion;
        assert(majorVersion != nil);
        
        [host setObject:majorVersion forUserDefaultsKey:SUSkippedMajorVersionKey];
        [host setObject:version forUserDefaultsKey:SUSkippedMajorSubreleaseVersionKey];
    } else {
        [host setObject:version forUserDefaultsKey:SUSkippedMinorVersionKey];
    }
}

@end
