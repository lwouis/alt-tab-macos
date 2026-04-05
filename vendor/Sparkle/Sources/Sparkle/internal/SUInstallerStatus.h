//
//  SUInstallerStatus.h
//  InstallerStatus
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerStatusProtocol.h"

// This object implements the protocol which we have defined. It provides the actual behavior for the service. It is 'exported' by the service to make it available to the process hosting the service over an NSXPCConnection.
SPU_OBJC_DIRECT_MEMBERS @interface SUInstallerStatus : NSObject <SUInstallerStatusProtocol>

- (instancetype)initWithRemote:(BOOL)remote;

- (instancetype)init NS_UNAVAILABLE;

@end
