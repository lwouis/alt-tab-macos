//
//  SPUInstallerDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SPUUpdaterDelegate;
@class SUHost, SUAppcastItem, SPUDownloadedUpdate;

@protocol SPUInstallerDriverDelegate <NSObject>

- (void)installerDidStartInstallingWithApplicationTerminated:(BOOL)applicationTerminated;
- (void)installerDidStartExtracting;
- (void)installerDidExtractUpdateWithProgress:(double)progress;
- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately;
- (void)installerWillFinishInstallationAndRelaunch:(BOOL)relaunch;
- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunch acknowledgement:(void(^)(void))acknowledgement;

- (void)installerIsRequestingAbortInstallWithError:(nullable NSError *)error;
- (void)installerDidFailToApplyDeltaUpdate;

@end

SPU_OBJC_DIRECT_MEMBERS @interface SPUInstallerDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater updaterDelegate:(nullable id<SPUUpdaterDelegate>)updaterDelegate delegate:(nullable id<SPUInstallerDriverDelegate>)delegate;

- (void)resumeInstallingUpdateWithUpdateItem:(SUAppcastItem *)updateItem systemDomain:(BOOL)systemDomain;

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler;

- (void)extractDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate silently:(BOOL)silently completion:(void (^)(NSError * _Nullable))completionHandler;

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI;

- (void)cancelUpdate;

- (void)abortInstall;

@end

NS_ASSUME_NONNULL_END
