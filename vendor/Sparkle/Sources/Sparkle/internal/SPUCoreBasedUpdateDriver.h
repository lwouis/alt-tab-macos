//
//  SPUCoreBasedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"
#import "SPUUserUpdateState.h"
#import "SPUUpdateCheck.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;
@protocol SPUUpdaterDelegate;

@protocol SPUCoreBasedUpdateDriverDelegate <NSObject>

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryAppcastItem;

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately;

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

- (void)downloadDriverWillBeginDownload;

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength;

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length;

- (void)coreDriverDidStartExtractingUpdate;

- (void)installerDidStartInstallingWithApplicationTerminated:(BOOL)applicationTerminated;

- (void)installerDidExtractUpdateWithProgress:(double)progress;

- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement;

@end

SPU_OBJC_DIRECT_MEMBERS @interface SPUCoreBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updateCheck:(SPUUpdateCheck)updateCheck updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUCoreBasedUpdateDriverDelegate>)delegate;

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock;

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background requiresSilentInstall:(BOOL)silentInstall;

- (void)resumeInstallingUpdate;

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate;

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem inBackground:(BOOL)background;

- (void)deferInformationalUpdate:(SUAppcastItem *)updateItem secondaryUpdate:(SUAppcastItem * _Nullable)secondaryUpdateItem;

- (void)extractDownloadedUpdate;

- (void)clearDownloadedUpdate;

- (void)finishInstallationWithResponse:(SPUUserUpdateChoice)installUpdateStatus displayingUserInterface:(BOOL)displayingUserInterface;

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
