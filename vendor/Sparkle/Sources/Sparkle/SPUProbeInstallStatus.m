//
//  SPUProbeInstallStatus.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUProbeInstallStatus.h"
#import "SPUXPCServiceInfo.h"
#import "SPUMessageTypes.h"
#import "SPUInstallationInfo.h"
#import "SPUSecureCoding.h"
#import "SUInstallerStatus.h"
#import "SUXPCInstallerStatus.h"
#import "SUConstants.h"
#import "SULog.h"


#include "AppKitPrevention.h"

// This timeout is if probing the installer takes too long
// It should be at least more than 1 second since a probe can take around that much time
#define PROBE_TIMEOUT 7

@implementation SPUProbeInstallStatus

+ (void)probeInstallerInProgressForHostBundleIdentifier:(NSString *)hostBundleIdentifier completion:(void (^)(BOOL))completionHandler
{
    id<SUInstallerStatusProtocol> installerStatus;
#if INSTALLER_STATUS_XPC_SERVICE_EMBEDDED
    if (SPUXPCServiceIsEnabled(SUEnableInstallerStatusServiceKey)) {
        installerStatus = [[SUXPCInstallerStatus alloc] init];
    } else
#endif
    {
        installerStatus = [[SUInstallerStatus alloc] initWithRemote:NO];
    }
    
    __block BOOL handledCompletion = NO;
    
    [installerStatus setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
            if (!handledCompletion) {
#pragma clang diagnostic pop
                completionHandler(NO);
                handledCompletion = YES;
            }
        });
    }];
    
    NSString *serviceName = SPUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier);
    [installerStatus setServiceName:serviceName];
    
    [installerStatus probeStatusConnectivityWithReply:^{
        dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
            if (!handledCompletion) {
#pragma clang diagnostic pop
                completionHandler(YES);
                handledCompletion = YES;
            }
        });
        [installerStatus invalidate];
    }];
    
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PROBE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!handledCompletion) {
#pragma clang diagnostic pop
            SULog(SULogLevelError, @"Timed out while probing installer progress. If your app is sandboxed, please see https://sparkle-project.org/documentation/sandboxing/#testing for the potential cause.");
            completionHandler(NO);
            handledCompletion = YES;
        }
        [installerStatus invalidate];
    });
}

+ (void)probeInstallerUpdateItemForHostBundleIdentifier:(NSString *)hostBundleIdentifier completion:(void (^)(SPUInstallationInfo  * _Nullable))completionHandler
{
    id<SUInstallerStatusProtocol> installerStatus = nil;
#if INSTALLER_STATUS_XPC_SERVICE_EMBEDDED
    if (SPUXPCServiceIsEnabled(SUEnableInstallerStatusServiceKey)) {
        installerStatus = [[SUXPCInstallerStatus alloc] init];
    } else
#endif
    {
        installerStatus = [[SUInstallerStatus alloc] initWithRemote:NO];
    }
    
    __block BOOL handledCompletion = NO;
    
    [installerStatus setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
            if (!handledCompletion) {
#pragma clang diagnostic pop
                completionHandler(nil);
                handledCompletion = YES;
            }
        });
    }];
    
    NSString *serviceName = SPUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier);
    [installerStatus setServiceName:serviceName];
    
    [installerStatus probeStatusInfoWithReply:^(NSData * _Nullable installationInfoData) {
        SPUInstallationInfo *installationInfo = nil;
        if (installationInfoData != nil) {
            installationInfo = (SPUInstallationInfo *)SPUUnarchiveRootObjectSecurely((NSData * _Nonnull)installationInfoData, [SPUInstallationInfo class]);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
            if (!handledCompletion) {
#pragma clang diagnostic pop
                completionHandler(installationInfo);
                handledCompletion = YES;
            }
        });
        
        [installerStatus invalidate];
    }];
    
#pragma clang diagnostic push
#if __has_warning("-Wcompletion-handler")
#pragma clang diagnostic ignored "-Wcompletion-handler"
#endif
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PROBE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!handledCompletion) {
#pragma clang diagnostic pop
            SULog(SULogLevelDefault, @"Timed out while probing installer info data. If your app is sandboxed, please see https://sparkle-project.org/documentation/sandboxing/#testing for the potential cause.");
            completionHandler(nil);
            handledCompletion = YES;
        }
        [installerStatus invalidate];
    });
}

@end
