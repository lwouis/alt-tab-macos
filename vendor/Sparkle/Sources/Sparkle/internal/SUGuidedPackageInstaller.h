//
//  SUGuidedPackageInstaller.h
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

/**
# Sparkle Guided Installations

A guided installation allows Sparkle to download and install a package (pkg) or multi-package (mpkg) without user interaction.

The installer package is installed using macOS's built-in command line installer, `/usr/sbin/installer`. No installation interface is shown to the user.

A guided installation can be started by applications other than the application being replaced. This is particularly useful where helper applications or agents are used.
*/

#if SPARKLE_BUILD_PACKAGE_SUPPORT

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

SPU_OBJC_DIRECT_MEMBERS @interface SUGuidedPackageInstaller : NSObject <SUInstallerProtocol>

- (instancetype)initWithPackagePath:(NSString *)packagePath homeDirectory:(NSString *)homeDirectory userName:(NSString *)userName;

@end

#endif
