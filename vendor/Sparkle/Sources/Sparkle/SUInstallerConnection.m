//
//  SUInstallerConnection.m
//  InstallerConnection
//
//  Created by Mayur Pawashe on 7/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerConnection.h"


#include "AppKitPrevention.h"

static NSString *SUInstallerConnectionKeepAliveReason = @"Installer Connection Keep Alive";

@interface SUInstallerConnection () <SUInstallerCommunicationProtocol>
@end

@implementation SUInstallerConnection
{
    NSXPCConnection *_connection;
    // Intentionally not weak for XPC reasons
    id<SUInstallerCommunicationProtocol> _delegate;
    
    void (^_invalidationBlock)(void);
    
    BOOL _disabledAutomaticTermination;
    BOOL _remote;
}

- (instancetype)initWithDelegate:(id<SUInstallerCommunicationProtocol>)delegate remote:(BOOL)remote
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        _remote = remote;
        
        if (remote) {
            // If we are a XPC service, protect it from being terminated until the invalidation handler is set
            _disabledAutomaticTermination = YES;
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUInstallerConnectionKeepAliveReason];
        }
    }
    return self;
}

- (void)enableAutomaticTermination SPU_OBJC_DIRECT
{
    if (_disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SUInstallerConnectionKeepAliveReason];
        _disabledAutomaticTermination = NO;
    }
}

- (void)_setInvalidationHandler:(void (^)(void))invalidationHandler SPU_OBJC_DIRECT
{
    _invalidationBlock = [invalidationHandler copy];
    
    // No longer needed because of invalidation callback
    [self enableAutomaticTermination];
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _setInvalidationHandler:invalidationHandler];
        });
    } else {
        [self _setInvalidationHandler:invalidationHandler];
    }
}

- (void)_setServiceName:(NSString *)serviceName systemDomain:(BOOL)systemDomain SPU_OBJC_DIRECT
{
    NSXPCConnectionOptions options = systemDomain ? NSXPCConnectionPrivileged : (NSXPCConnectionOptions)0;
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:serviceName options:options];
    
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    connection.exportedObject = _delegate;
    
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    
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
                [strongSelf _invalidate];
            }
        });
    };
    
    [_connection resume];
}

- (void)setServiceName:(NSString *)serviceName systemDomain:(BOOL)systemDomain
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _setServiceName:serviceName systemDomain:systemDomain];
        });
    } else {
        [self _setServiceName:serviceName systemDomain:systemDomain];
    }
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(id<SUInstallerCommunicationProtocol>)self->_connection.remoteObjectProxy handleMessageWithIdentifier:identifier data:data];
        });
    } else {
        [(id<SUInstallerCommunicationProtocol>)_connection.remoteObjectProxy handleMessageWithIdentifier:identifier data:data];
    }
}

- (void)_invalidate SPU_OBJC_DIRECT
{
    if (_invalidationBlock != nil) {
        _invalidationBlock();
        _invalidationBlock = nil;
    }
    
    // Break the retain cycle
    _delegate = nil;
    
    [self enableAutomaticTermination];
}

// This method can be called from us or a remote
- (void)invalidate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_connection invalidate];
        self->_connection = nil;
        
        [self _invalidate];
    });
}

@end
