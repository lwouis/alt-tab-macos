//
//  SPUUserAgent+Private.m
//  Sparkle
//
//  Created by Mayur Pawashe on 11/12/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUUserAgent+Private.h"
#import "SUHost.h"

NSString *SPUMakeUserAgentWithBundle(NSBundle *responsibleBundle, NSString * _Nullable displayNameSuffix)
{
    SUHost *responsibleHost = [[SUHost alloc] initWithBundle:responsibleBundle];
    return SPUMakeUserAgentWithHost(responsibleHost, displayNameSuffix);
}

NSString *SPUMakeUserAgentWithHost(SUHost *responsibleHost, NSString * _Nullable displayNameSuffix)
{
    NSString *displayVersion = responsibleHost.displayVersion;
    
    NSString *userAgent = [NSString stringWithFormat:@"%@%@/%@ Sparkle/%@", responsibleHost.name, (displayNameSuffix != nil ? displayNameSuffix : @""), (displayVersion.length > 0 ? displayVersion : @"?"), @""MARKETING_VERSION];
    NSData *cleanedAgent = [userAgent dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSString *result;
    if (cleanedAgent != nil) {
        NSString *cleanedAgentString = [[NSString alloc] initWithData:(NSData * _Nonnull)cleanedAgent encoding:NSASCIIStringEncoding];
        if (cleanedAgentString != nil) {
            result = cleanedAgentString;
        } else {
            result = @"";
        }
    } else {
        result = @"";
    }
    
    return result;
}
