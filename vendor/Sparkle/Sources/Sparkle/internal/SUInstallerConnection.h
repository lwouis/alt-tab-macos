//
//  SUInstallerConnection.h
//  InstallerConnection
//
//  Created by Mayur Pawashe on 7/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerConnectionProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
SPU_OBJC_DIRECT_MEMBERS @interface SUInstallerConnection : NSObject <SUInstallerConnectionProtocol>

// Due to XPC reasons, this delegate is strongly referenced, until it's invalidated
- (instancetype)initWithDelegate:(id<SUInstallerCommunicationProtocol>)delegate remote:(BOOL)remote;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
