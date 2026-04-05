//
//  SUInstallerLauncherProtocol.h
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerLauncherStatus.h"

@protocol SUInstallerLauncherProtocol

- (void)launchInstallerWithHostBundlePath:(NSString *)hostBundlePath mainBundlePath:(NSString *)mainBundlePath installationType:(NSString *)installationType allowingDriverInteraction:(BOOL)allowingDriverInteraction completion:(void (^)(SUInstallerLauncherStatus, BOOL))completionHandler;
    
@end
