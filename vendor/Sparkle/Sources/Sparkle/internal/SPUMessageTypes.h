//
//  SPUMessageTypes.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Order matters; higher stages have higher values.
typedef NS_ENUM(int32_t, SPUInstallerMessageType)
{
    SPUInstallerNotStarted = 0,
    SPUExtractionStarted = 1,
    SPUExtractedArchiveWithProgress = 2,
    SPUArchiveExtractionFailed = 3,
    SPUValidationStarted = 4,
    SPUInstallationStartedStage1 = 5,
    SPUInstallationFinishedStage1 = 6,
    SPUInstallationFinishedStage2 = 7,
    SPUInstallationFinishedStage3 = 8,
    SPUUpdaterAlivePing = 9,
    SPUInstallerError = 10
};

typedef NS_ENUM(int32_t, SPUUpdaterMessageType)
{
    SPUInstallationData = 0,
    SPUSentUpdateAppcastItemData = 1,
    SPUResumeInstallationToStage2 = 2,
    SPUUpdaterAlivePong = 3,
    SPUCancelInstallation = 4
};

BOOL SPUInstallerMessageTypeIsLegal(SPUInstallerMessageType oldMessageType, SPUInstallerMessageType newMessageType);

// Used by framework to communicate to installer (Autoupdate)
NSString *SPUInstallerServiceNameForBundleIdentifier(NSString *bundleIdentifier);

// Used by framework to communicate to progress agent tool (Updater)
NSString *SPUStatusInfoServiceNameForBundleIdentifier(NSString *bundleIdentifier);

// Used by progress agent tool to communicate to installer (Autoupdate)
NSString *SPUProgressAgentServiceNameForBundleIdentifier(NSString *bundleIdentifier);

NS_ASSUME_NONNULL_END
