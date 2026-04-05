//
//  SUApplicationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import "SUApplicationInfo.h"
#import "SUHost.h"
#import <AppKit/AppKit.h>

@implementation SUApplicationInfo

+ (BOOL)isBackgroundApplication:(NSApplication *)application
{
    return (application.activationPolicy == NSApplicationActivationPolicyAccessory);
}

+ (NSImage *)bestIconForHost:(SUHost *)host
{
    BOOL isMainBundle = [host.bundle isEqualTo:[NSBundle mainBundle]];
 
    // First try NSImageNameApplicationIcon. This image can be dynamically updated if the user's system icon settings change.
    NSImage *icon = isMainBundle ? [NSImage imageNamed:NSImageNameApplicationIcon] : nil;
    
    // Next try asking NSWorkspace for icon of the bundle
    if (icon == nil) {
        icon = [[NSWorkspace sharedWorkspace] iconForFile:host.bundlePath];
    }
    
    return icon;
}

@end

#endif
