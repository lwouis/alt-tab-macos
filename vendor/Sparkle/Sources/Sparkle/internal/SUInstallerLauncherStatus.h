//
//  SUInstallerLauncherStatus.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, SUInstallerLauncherStatus)
{
    SUInstallerLauncherSuccess = 0,
    SUInstallerLauncherCanceled = 1,
    SUInstallerLauncherAuthorizeLater = 3,
    SUInstallerLauncherFailure = 4
};
