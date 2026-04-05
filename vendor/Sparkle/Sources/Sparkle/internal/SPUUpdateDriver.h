//
//  SPUUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol SPUResumableUpdate;

typedef void (^SPUUpdateDriverCompletion)(BOOL shouldShowUpdateImmediately, id<SPUResumableUpdate> _Nullable resumableUpdate, NSError * _Nullable error);

// This protocol describes an update driver that drives updates
// An update driver may have multiple levels of other controller components (eg: basic update driver, core based update driver, ui based update driver, appcast driver, etc)
// The update driver and the components the driver has communicates via parameter passing and delegation..
// The old Sparkle architecture communicated via subclassing and method overriding, but this lead to bugs due to high coupling, and complexity of not being aware of methods being executed.
// The newer architecture is still complex but should be more reliable to maintain and extend.
@protocol SPUUpdateDriver <NSObject>

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock;

- (void)setUpdateShownHandler:(void (^)(void))updateShownHandler;

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders;

- (void)resumeInstallingUpdate;

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate;

@property (nonatomic, readonly) BOOL showingUpdate;

// A likely implementation of -abortUpdate is invoking -abortUpdateWithError: by passing nil
- (void)abortUpdate;

// This should be invoked on the update driver to finish the update driver's work
- (void)abortUpdateWithError:(NSError * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
