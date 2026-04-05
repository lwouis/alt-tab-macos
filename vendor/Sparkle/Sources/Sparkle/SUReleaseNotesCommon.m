//
//  SUReleaseNotesCommon.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/31/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUReleaseNotesCommon.h"


#include "AppKitPrevention.h"

BOOL SUReleaseNotesIsSafeURL(NSURL *url, NSArray<NSString *> *customAllowedURLSchemes, BOOL *isAboutBlankURL)
{
    NSString *scheme = url.scheme;
    BOOL isAboutBlank = [url.absoluteString isEqualToString:@"about:blank"] || [url.absoluteString isEqualToString:@"about:srcdoc"];
    BOOL safeURL = isAboutBlank || [@[@"http", @"https", @"macappstore", @"macappstores", @"itms-apps", @"itms-appss"] containsObject:scheme] || [customAllowedURLSchemes containsObject:scheme.lowercaseString];
    
    *isAboutBlankURL = isAboutBlank;
    
    return safeURL;
}

#endif
