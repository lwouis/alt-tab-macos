//
//  SUXPCServiceInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUXPCServiceInfo.h"
#import "SUErrors.h"
#import "SUConstants.h"
#import "SUHost.h"

#include "AppKitPrevention.h"

BOOL SPUXPCServiceIsEnabled(NSString *enabledKey)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    SUHost *mainBundleHost = [[SUHost alloc] initWithBundle:mainBundle];
    
    return [mainBundleHost boolForInfoDictionaryKey:enabledKey];
}

BOOL SPUHelperHasExecutablePermission(NSString *component, NSString * _Nullable __autoreleasing * _Nullable failureReason)
{
    NSBundle *sparkleBundle = [NSBundle bundleWithIdentifier:SUBundleIdentifier];
    NSURL *helperURL = [[sparkleBundle.bundleURL URLByAppendingPathComponent:component isDirectory:NO] URLByResolvingSymlinksInPath];
    
    NSString *helperPath = helperURL.path;
    
    NSError *attributesError = nil;
    NSDictionary<NSFileAttributeKey, id> *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:helperPath error:&attributesError];
    
    if (attributes == nil) {
        if (failureReason != NULL) {
            *failureReason = [NSString stringWithFormat:@"Failed to fetch info from file '%@' -- does this helper exist? %@", helperPath, attributesError.localizedDescription];
        }
        
        return NO;
    }
    
    NSNumber *posixPermissions = attributes[NSFilePosixPermissions];
    
    if (posixPermissions != nil) {
        mode_t mode = posixPermissions.unsignedShortValue;
        if (((mode & S_IXUSR) == 0 || (mode & S_IXGRP) == 0 || (mode & S_IXOTH) == 0)) {
            if (failureReason != NULL) {
                *failureReason = [NSString stringWithFormat:@"The file '%@' may not have executable permissions -- were they lost during a bad file copy? Please ensure file permissions and symbolic links for Sparkle framework are preserved.", helperPath];
            }
            
            return NO;
        }
    }
    
    return YES;
}

BOOL SPUXPCServiceHasExecutablePermission(NSString *serviceName, NSString * _Nullable __autoreleasing * _Nullable failureReason)
{
    NSString *componentName = [NSString stringWithFormat:@"XPCServices/%@.xpc/Contents/MacOS/%@", serviceName, serviceName];
    
    return SPUHelperHasExecutablePermission(componentName, failureReason);
}
