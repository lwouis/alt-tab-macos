//
//  SUXPCInstallerStatus.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if INSTALLER_STATUS_XPC_SERVICE_EMBEDDED

#import <Foundation/Foundation.h>
#import "SUInstallerStatusProtocol.h"

@interface SUXPCInstallerStatus : NSObject <SUInstallerStatusProtocol>

@end

#endif
