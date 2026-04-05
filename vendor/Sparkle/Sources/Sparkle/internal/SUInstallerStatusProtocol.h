//
//  SUInstallerStatusProtocol.h
//  InstallerStatus
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusInfoProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUInstallerStatusProtocol

// Even though this is declared in SUStatusInfoProtocol, we should declare it here because macOS 10.8 doesn't traverse adopted protocols,
// which is why this protocol doesn't adopt SUStatusInfoProtocol
- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply;

// Even though this is declared in SUStatusInfoProtocol, we should declare it here because macOS 10.8 doesn't traverse adopted protocols,
// which is why this protocol doesn't adopt SUStatusInfoProtocol
- (void)probeStatusConnectivityWithReply:(void (^)(void))reply;

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler;

- (void)setServiceName:(NSString *)serviceName;

- (void)invalidate;
    
@end

NS_ASSUME_NONNULL_END
