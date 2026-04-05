//
//  SUXPCInstallerConnection.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if INSTALLER_CONNECTION_XPC_SERVICE_EMBEDDED

#import "SUXPCInstallerConnection.h"


#include "AppKitPrevention.h"

@implementation SUXPCInstallerConnection
{
    NSXPCConnection *_connection;
    // Intentionally not weak for XPC reasons
    id<SUInstallerCommunicationProtocol> _delegate;
    
    void (^_invalidationBlock)(void);
}

- (instancetype)initWithDelegate:(id<SUInstallerCommunicationProtocol>)delegate
{
    self = [super init];
    if (self != nil) {
        _connection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_CONNECTION_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerConnectionProtocol)];
        
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
        
        _delegate = delegate;
        
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
        _connection.exportedObject = _delegate;
        
        [_connection resume];
    }
    return self;
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    _invalidationBlock = [invalidationHandler copy];
    
    __weak __typeof__(self) weakSelf = self;
    [(id<SUInstallerConnectionProtocol>)_connection.remoteObjectProxy setInvalidationHandler:^{
        [weakSelf invokeInvalidation];
    }];
}

- (void)setServiceName:(NSString *)serviceName systemDomain:(BOOL)systemDomain
{
    [(id<SUInstallerConnectionProtocol>)_connection.remoteObjectProxy setServiceName:serviceName systemDomain:systemDomain];
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    [(id<SUInstallerConnectionProtocol>)_connection.remoteObjectProxy handleMessageWithIdentifier:identifier data:data];
}

- (void)invalidate
{
    [(id<SUInstallerConnectionProtocol>)_connection.remoteObjectProxy invalidate];
    [_connection invalidate];
    _connection = nil;
}

- (void)invokeInvalidation SPU_OBJC_DIRECT
{
    if (_invalidationBlock != nil) {
        _invalidationBlock();
        _invalidationBlock = nil;
    }
    // Break our retain cycle
    _delegate = nil;
}

@end

#endif
