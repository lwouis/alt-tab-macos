//
//  SPUUpdatePermissionRequest.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdatePermissionRequest.h"


#include "AppKitPrevention.h"

static NSString *SPUUpdatePermissionRequestSystemProfileKey = @"SPUUpdatePermissionRequestSystemProfile";

@implementation SPUUpdatePermissionRequest

@synthesize systemProfile = _systemProfile;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    NSArray<NSDictionary<NSString *, NSString *> *> *systemProfile = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [NSDictionary class], [NSString class]]] forKey:SPUUpdatePermissionRequestSystemProfileKey];
    if (systemProfile == nil) {
        return nil;
    }
    
    return [self initWithSystemProfile:systemProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:_systemProfile forKey:SPUUpdatePermissionRequestSystemProfileKey];
}

- (instancetype)initWithSystemProfile:(NSArray<NSDictionary<NSString *, NSString *> *> *)systemProfile
{
    self = [super init];
    if (self != nil) {
        _systemProfile = systemProfile;
    }
    return self;
}

@end
