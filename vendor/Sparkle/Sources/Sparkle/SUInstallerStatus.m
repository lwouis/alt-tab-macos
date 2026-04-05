//
//  SUInstallerStatus.m
//  InstallerStatus
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerStatus.h"


#include "AppKitPrevention.h"

@implementation SUInstallerStatus
{
    NSXPCConnection *_connection;
    
    void (^_invalidationBlock)(void);
    
    BOOL _remote;
}

- (instancetype)initWithRemote:(BOOL)remote
{
    self = [super init];
    if (self != nil) {
        _remote = remote;
    }
    return self;
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_invalidationBlock = [invalidationHandler copy];
        });
    } else {
        _invalidationBlock = [invalidationHandler copy];
    }
}

- (void)_setServiceName:(NSString *)serviceName SPU_OBJC_DIRECT
{
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:serviceName options:(NSXPCConnectionOptions)0];
    
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUStatusInfoProtocol)];
    
    _connection = connection;
    
    __weak __typeof__(self) weakSelf = self;
    _connection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf->_connection invalidate];
            }
        });
    };
    
    _connection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf->_connection = nil;
                [strongSelf _invokeInvalidationBlock];
            }
        });
    };
    
    [_connection resume];
}

- (void)setServiceName:(NSString *)serviceName
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _setServiceName:serviceName];
        });
    } else {
        [self _setServiceName:serviceName];
    }
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(id<SUStatusInfoProtocol>)self->_connection.remoteObjectProxy probeStatusInfoWithReply:reply];
        });
    } else {
        [(id<SUStatusInfoProtocol>)_connection.remoteObjectProxy probeStatusInfoWithReply:reply];
    }
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(id<SUStatusInfoProtocol>)self->_connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
        });
    } else {
        [(id<SUStatusInfoProtocol>)_connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
    }
}

- (void)_invokeInvalidationBlock SPU_OBJC_DIRECT
{
    if (_invalidationBlock != nil) {
        _invalidationBlock();
        _invalidationBlock = nil;
    }
}

// This method can be called from us or a remote
- (void)invalidate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_connection invalidate];
        self->_connection = nil;
        
        [self _invokeInvalidationBlock];
    });
}

@end
