//
//  SPUUserInitiatedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost;
@protocol SPUUpdaterDelegate, SPUUserDriver;

SPU_OBJC_DIRECT_MEMBERS @interface SPUUserInitiatedUpdateDriver : NSObject <SPUUpdateDriver>

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate;

@end

NS_ASSUME_NONNULL_END
