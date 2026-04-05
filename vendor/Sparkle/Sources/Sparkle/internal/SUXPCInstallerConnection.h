//
//  SUXPCInstallerConnection.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if INSTALLER_CONNECTION_XPC_SERVICE_EMBEDDED

#import <Foundation/Foundation.h>
#import "SUInstallerConnectionProtocol.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUXPCInstallerConnection : NSObject <SUInstallerConnectionProtocol>

// Due to XPC reasons, this delegate is strongly referenced, until it's invalidated
- (instancetype)initWithDelegate:(id<SUInstallerCommunicationProtocol>)delegate;

@end

NS_ASSUME_NONNULL_END

#endif
