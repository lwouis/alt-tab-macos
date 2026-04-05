//
//  SPUUIBasedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SPUUIBasedUpdateDriverDelegate <NSObject>

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;
- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;
- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)uiDriverDidShowUpdate;
- (void)basicDriverDidFinishLoadingAppcast;

@end

@class SUHost;
@protocol SPUUserDriver, SPUUpdaterDelegate;

SPU_OBJC_DIRECT_MEMBERS @interface SPUUIBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver userInitiated:(BOOL)userInitiated updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUUIBasedUpdateDriverDelegate>)delegate;

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock;

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background;

- (void)resumeInstallingUpdate;

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate;

- (void)abortUpdateWithError:(nullable NSError *)error showErrorToUser:(BOOL)showedUserProgress;

@end

NS_ASSUME_NONNULL_END
