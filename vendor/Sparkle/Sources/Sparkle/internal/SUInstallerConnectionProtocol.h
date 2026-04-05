//
//  SUInstallerConnectionProtocol.h
//  InstallerConnection
//
//  Created by Mayur Pawashe on 7/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerCommunicationProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUInstallerConnectionProtocol

// This method is declared in SUInstallerCommunicationProtocol too
// the XPC decoder on macOS 10.8 doesn't follow protocols that adopt other protocols, which is why this protocol doesn't adopt SUInstallerCommunicationProtocol
- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data;

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler;

- (void)setServiceName:(NSString *)serviceName systemDomain:(BOOL)systemDomain;

- (void)invalidate;
    
@end

NS_ASSUME_NONNULL_END
