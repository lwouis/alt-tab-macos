//
//  SUInstallerLauncher.h
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerLauncherProtocol.h"

// Non-sandboxed XPC service used for launching our installer
// This is necessary for sandboxed applications
@interface SUInstallerLauncher : NSObject <SUInstallerLauncherProtocol>
@end
