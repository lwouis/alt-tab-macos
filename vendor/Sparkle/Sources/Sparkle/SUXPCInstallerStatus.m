//
//  SUXPCInstallerStatus.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if INSTALLER_STATUS_XPC_SERVICE_EMBEDDED

#import "SUXPCInstallerStatus.h"


#include "AppKitPrevention.h"

@implementation SUXPCInstallerStatus
{
    NSXPCConnection *_connection;
    
    void (^_invalidationBlock)(void);
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _connection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_STATUS_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerStatusProtocol)];
        
        __weak __typeof__(self) weakSelf = self;
        _connection.invalidationHandler = ^{
            [weakSelf invokeInvalidation];
        };
        
        _connection.interruptionHandler = ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf invokeInvalidation];
                [strongSelf->_connection invalidate];
            }
        };
        
        [_connection resume];
    }
    return self;
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    _invalidationBlock = [invalidationHandler copy];
    
    __weak __typeof__(self) weakSelf = self;
    [(id<SUInstallerStatusProtocol>)_connection.remoteObjectProxy setInvalidationHandler:^{
        [weakSelf invokeInvalidation];
    }];
}

- (void)setServiceName:(NSString *)serviceName
{
    [(id<SUInstallerStatusProtocol>)_connection.remoteObjectProxy setServiceName:serviceName];
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply
{
    [(id<SUInstallerStatusProtocol>)_connection.remoteObjectProxy probeStatusInfoWithReply:reply];
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    [(id<SUInstallerStatusProtocol>)_connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
}

- (void)invalidate
{
    [(id<SUInstallerStatusProtocol>)_connection.remoteObjectProxy invalidate];
    [_connection invalidate];
    _connection = nil;
}

- (void)invokeInvalidation
{
    if (_invalidationBlock != nil) {
        _invalidationBlock();
        _invalidationBlock = nil;
    }
}

@end

#endif
