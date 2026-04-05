//
//  SUApplicationInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost, NSImage, NSApplication;

SPU_OBJC_DIRECT_MEMBERS @interface SUApplicationInfo : NSObject

+ (BOOL)isBackgroundApplication:(NSApplication *)application;

+ (NSImage *)bestIconForHost:(SUHost *)host;

@end

NS_ASSUME_NONNULL_END

#endif
