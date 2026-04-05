//
//  SUPlainInstaller.h
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerProtocol.h"

@class SUHost;
@protocol SUVersionComparison;

SPU_OBJC_DIRECT_MEMBERS @interface SUPlainInstaller : NSObject <SUInstallerProtocol>

/**
 @param host The current (old) bundle host
 @param bundlePath The path to the new bundle that will be installed.
 @param installationPath The path the new bundlePath will be installed to.
 */
- (instancetype)initWithHost:(SUHost *)host bundlePath:(NSString *)bundlePath installationPath:(NSString *)installationPath;

@end
