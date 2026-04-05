//
//  SUUpdatePermissionResponse.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdatePermissionResponse.h"


#include "AppKitPrevention.h"

static NSString *SUUpdatePermissionAutomaticUpdateChecksKey = @"SUUpdatePermissionAutomaticUpdateChecks";
static NSString *SUUpdatePermissionAutomaticUpdateDownloadingKey = @"SUUpdatePermissionAutomaticUpdateDownloading";
static NSString *SUUpdatePermissionSendSystemProfileKey = @"SUUpdatePermissionSendSystemProfile";

@implementation SUUpdatePermissionResponse

@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize sendSystemProfile = _sendSystemProfile;
@synthesize automaticUpdateDownloading = _automaticUpdateDownloading;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    BOOL automaticUpdateChecks = [decoder decodeBoolForKey:SUUpdatePermissionAutomaticUpdateChecksKey];
    NSNumber *automaticUpdateDownloading = [decoder decodeObjectOfClass:[NSNumber class] forKey:SUUpdatePermissionAutomaticUpdateDownloadingKey];
    BOOL sendSystemProfile = [decoder decodeBoolForKey:SUUpdatePermissionSendSystemProfileKey];
    return [self initWithAutomaticUpdateChecks:automaticUpdateChecks automaticUpdateDownloading:automaticUpdateDownloading sendSystemProfile:sendSystemProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeBool:_automaticUpdateChecks forKey:SUUpdatePermissionAutomaticUpdateChecksKey];
    
    if (_automaticUpdateDownloading != nil) {
        [encoder encodeObject:_automaticUpdateDownloading forKey:SUUpdatePermissionAutomaticUpdateDownloadingKey];
    }
    
    [encoder encodeBool:_sendSystemProfile forKey:SUUpdatePermissionSendSystemProfileKey];
}

- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks automaticUpdateDownloading:(NSNumber * _Nullable)automaticUpdateDownloading sendSystemProfile:(BOOL)sendSystemProfile
{
    self = [super init];
    if (self != nil) {
        _automaticUpdateChecks = automaticUpdateChecks;
        _automaticUpdateDownloading = automaticUpdateDownloading;
        _sendSystemProfile = sendSystemProfile;
    }
    return self;
}

- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks sendSystemProfile:(BOOL)sendSystemProfile
{
    return [self initWithAutomaticUpdateChecks:automaticUpdateChecks automaticUpdateDownloading:nil sendSystemProfile:sendSystemProfile];
}

@end
