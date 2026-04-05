//
//  SUConstants.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//


#ifndef SUCONSTANTS_H
#define SUCONSTANTS_H

#import <Foundation/Foundation.h>

// -----------------------------------------------------------------------------
//	Misc:
// -----------------------------------------------------------------------------

extern NSString *const SUBundleIdentifier;

extern NSString *const SUAppcastAttributeValueMacOS;

// -----------------------------------------------------------------------------
//	Notifications:
// -----------------------------------------------------------------------------

extern NSString *const SUUpdateAutomaticCheckSettingChangedNotification;
extern NSString *const SUUpdateSettingsNeedsSynchronizationNotification;
extern NSString *const SUUpdateBundlePathUserInfoKey;

// -----------------------------------------------------------------------------
//	PList keys::
// -----------------------------------------------------------------------------

extern NSString *const SUFeedURLKey;
extern NSString *const SUHasLaunchedBeforeKey;
extern NSString *const SURelaunchHostBundleKey;
extern NSString *const SUShowReleaseNotesKey;
extern NSString *const SUSkippedMinorVersionKey;
extern NSString *const SUSkippedMajorVersionKey;
extern NSString *const SUSkippedMajorSubreleaseVersionKey;
extern NSString *const SUScheduledCheckIntervalKey;
extern NSString *const SUScheduledImpatientCheckIntervalKey;
extern NSString *const SULastCheckTimeKey;
extern NSString *const SUSignedFeedFailureExpirationIntervalKey;
extern NSString *const SUPublicDSAKeyKey;
extern NSString *const SUPublicDSAKeyFileKey;
extern NSString *const SUPublicEDKeyKey;
extern NSString *const SURequireSignedFeedKey;
extern NSString *const SUVerifyUpdateBeforeExtractionKey;
extern NSString *const SUAutomaticallyUpdateKey;
extern NSString *const SUAllowsAutomaticUpdatesKey;
extern NSString *const SUEnableAutomaticChecksKey;
extern NSString *const SUEnableInstallerLauncherServiceKey;
extern NSString *const SUEnableDownloaderServiceKey;
extern NSString *const SUEnableInstallerConnectionServiceKey;
extern NSString *const SUEnableInstallerStatusServiceKey;
extern NSString *const SUEnableSystemProfilingKey;
extern NSString *const SUSendProfileInfoKey;
extern NSString *const SUUpdateGroupIdentifierKey;
extern NSString *const SULastProfileSubmitDateKey;
extern NSString *const SUPromptUserOnFirstLaunchKey;
extern NSString *const SUDefaultsDomainKey;
extern NSString *const SUEnableJavaScriptKey;
extern NSString *const SUAllowedURLSchemesKey;

// -----------------------------------------------------------------------------
//	Appcast keys::
// -----------------------------------------------------------------------------

extern NSString *const SUAppcastAttributeDeltaFrom;
extern NSString *const SUAppcastAttributeDeltaFromSparkleExecutableSize;
extern NSString *const SUAppcastAttributeDeltaFromSparkleLocales;
extern NSString *const SUAppcastAttributeDSASignature;
extern NSString *const SUAppcastAttributeEDSignature;
extern NSString *const SUAppcastAttributeShortVersionString;
extern NSString *const SUAppcastAttributeVersion;
extern NSString *const SUAppcastAttributeOsType;
extern NSString *const SUAppcastAttributeInstallationType;
extern NSString *const SUAppcastAttributeFormat;
extern NSString *const SUAppcastAttributeLength;

extern NSString *const SUAppcastElementVersion;
extern NSString *const SUAppcastElementShortVersionString;
extern NSString *const SUAppcastElementCriticalUpdate;
extern NSString *const SUAppcastElementDeltas;
extern NSString *const SUAppcastElementMinimumAutoupdateVersion;
extern NSString *const SUAppcastElementMinimumSystemVersion;
extern NSString *const SUAppcastElementMaximumSystemVersion;
extern NSString *const SUAppcastElementMinimumUpdateVersion;
extern NSString *const SUAppcastElementHardwareRequirements;
extern NSString *const SUAppcastElementHardwareRequirementARM64;
extern NSString *const SUAppcastElementReleaseNotesLink;
extern NSString *const SUAppcastElementFullReleaseNotesLink;
extern NSString *const SUAppcastElementTags;
extern NSString *const SUAppcastElementPhasedRolloutInterval;
extern NSString *const SUAppcastElementInformationalUpdate;
extern NSString *const SUAppcastElementChannel;
extern NSString *const SUAppcastElementBelowVersion;
extern NSString *const SUAppcastElementIgnoreSkippedUpgradesBelowVersion;

extern NSString *const SURSSAttributeURL;
extern NSString *const SURSSAttributeLength;

extern NSString *const SURSSElementDescription;
extern NSString *const SURSSElementEnclosure;
extern NSString *const SURSSElementLink;
extern NSString *const SURSSElementPubDate;
extern NSString *const SURSSElementTitle;

extern NSString *const SUXMLLanguage;

#endif
