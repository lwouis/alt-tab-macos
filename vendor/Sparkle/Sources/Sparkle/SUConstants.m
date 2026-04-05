//
//  SUConstants.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUConstants.h"
#import "SUErrors.h"

#include "AppKitPrevention.h"

NSString *const SUBundleIdentifier = @SPARKLE_BUNDLE_IDENTIFIER;

NSString *const SUAppcastAttributeValueMacOS = @"macos";

NSString *const SUUpdateAutomaticCheckSettingChangedNotification = @"SUUpdateAutomaticCheckSettingChanged";
NSString *const SUUpdateSettingsNeedsSynchronizationNotification = @"SUUpdateSettingsNeedsSynchronization";
NSString *const SUUpdateBundlePathUserInfoKey = @"SUBundlePath";

NSString *const SUFeedURLKey = @"SUFeedURL";
NSString *const SUHasLaunchedBeforeKey = @"SUHasLaunchedBefore";
NSString *const SURelaunchHostBundleKey = @"SURelaunchHostBundle";
NSString *const SUShowReleaseNotesKey = @"SUShowReleaseNotes";
NSString *const SUSkippedMinorVersionKey = @"SUSkippedVersion";
NSString *const SUSkippedMajorVersionKey = @"SUSkippedMajorVersion";
NSString *const SUSkippedMajorSubreleaseVersionKey = @"SUSkippedMajorSubreleaseVersion";
NSString *const SUScheduledCheckIntervalKey = @"SUScheduledCheckInterval";
NSString *const SUScheduledImpatientCheckIntervalKey = @"SUScheduledImpatientCheckInterval";
NSString *const SULastCheckTimeKey = @"SULastCheckTime";
NSString *const SUSignedFeedFailureExpirationIntervalKey = @"SUSignedFeedFailureExpirationInterval";
NSString *const SUPublicDSAKeyKey = @"SUPublicDSAKey";
NSString *const SUPublicDSAKeyFileKey = @"SUPublicDSAKeyFile";
NSString *const SUPublicEDKeyKey = @"SUPublicEDKey";
NSString *const SURequireSignedFeedKey = @"SURequireSignedFeed";
NSString *const SUVerifyUpdateBeforeExtractionKey = @"SUVerifyUpdateBeforeExtraction";
NSString *const SUAutomaticallyUpdateKey = @"SUAutomaticallyUpdate";
NSString *const SUAllowsAutomaticUpdatesKey = @"SUAllowsAutomaticUpdates";
NSString *const SUEnableSystemProfilingKey = @"SUEnableSystemProfiling";
NSString *const SUEnableAutomaticChecksKey = @"SUEnableAutomaticChecks";
NSString *const SUEnableInstallerLauncherServiceKey = @"SUEnableInstallerLauncherService";
NSString *const SUEnableDownloaderServiceKey = @"SUEnableDownloaderService";
NSString *const SUEnableInstallerConnectionServiceKey = @"SUEnableInstallerConnectionService";
NSString *const SUEnableInstallerStatusServiceKey = @"SUEnableInstallerStatusService";
NSString *const SUSendProfileInfoKey = @"SUSendProfileInfo";
NSString *const SUUpdateGroupIdentifierKey = @"SUUpdateGroupIdentifier";
NSString *const SULastProfileSubmitDateKey = @"SULastProfileSubmissionDate";
NSString *const SUPromptUserOnFirstLaunchKey = @"SUPromptUserOnFirstLaunch";
NSString *const SUEnableJavaScriptKey = @"SUEnableJavaScript";
NSString *const SUAllowedURLSchemesKey = @"SUAllowedURLSchemes";
NSString *const SUDefaultsDomainKey = @"SUDefaultsDomain";
NSString *const SUSparkleErrorDomain = @"SUSparkleErrorDomain";
NSString *const SPUNoUpdateFoundReasonKey = @"SUNoUpdateFoundReason";
NSString *const SPUNoUpdateFoundUserInitiatedKey = @"SPUNoUpdateUserInitiated";
NSString *const SPULatestAppcastItemFoundKey = @"SULatestAppcastItemFound";

NSString *const SUAppcastAttributeDeltaFrom = @"sparkle:deltaFrom";
NSString *const SUAppcastAttributeDeltaFromSparkleExecutableSize = @"sparkle:deltaFromSparkleExecutableSize";
NSString *const SUAppcastAttributeDeltaFromSparkleLocales = @"sparkle:deltaFromSparkleLocales";
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT || GENERATE_APPCAST_BUILD_LEGACY_DSA_SUPPORT
NSString *const SUAppcastAttributeDSASignature = @"sparkle:dsaSignature";
#endif
NSString *const SUAppcastAttributeEDSignature = @"sparkle:edSignature";
NSString *const SUAppcastAttributeShortVersionString = @"sparkle:shortVersionString";
NSString *const SUAppcastAttributeVersion = @"sparkle:version";
NSString *const SUAppcastAttributeOsType = @"sparkle:os";
NSString *const SUAppcastAttributeInstallationType = @"sparkle:installationType";
NSString *const SUAppcastAttributeFormat = @"sparkle:format";
NSString *const SUAppcastAttributeLength = @"sparkle:length";

NSString *const SUAppcastElementVersion = SUAppcastAttributeVersion;
NSString *const SUAppcastElementShortVersionString = SUAppcastAttributeShortVersionString;
NSString *const SUAppcastElementCriticalUpdate = @"sparkle:criticalUpdate";
NSString *const SUAppcastElementDeltas = @"sparkle:deltas";
NSString *const SUAppcastElementMinimumAutoupdateVersion = @"sparkle:minimumAutoupdateVersion";
NSString *const SUAppcastElementMinimumSystemVersion = @"sparkle:minimumSystemVersion";
NSString *const SUAppcastElementMaximumSystemVersion = @"sparkle:maximumSystemVersion";
NSString *const SUAppcastElementMinimumUpdateVersion = @"sparkle:minimumUpdateVersion";
NSString *const SUAppcastElementHardwareRequirements = @"sparkle:hardwareRequirements";
NSString *const SUAppcastElementHardwareRequirementARM64 = @"arm64";
NSString *const SUAppcastElementReleaseNotesLink = @"sparkle:releaseNotesLink";
NSString *const SUAppcastElementFullReleaseNotesLink = @"sparkle:fullReleaseNotesLink";
NSString *const SUAppcastElementTags = @"sparkle:tags";
NSString *const SUAppcastElementPhasedRolloutInterval = @"sparkle:phasedRolloutInterval";
NSString *const SUAppcastElementInformationalUpdate = @"sparkle:informationalUpdate";
NSString *const SUAppcastElementChannel = @"sparkle:channel";
NSString *const SUAppcastElementBelowVersion = @"sparkle:belowVersion";
NSString *const SUAppcastElementIgnoreSkippedUpgradesBelowVersion = @"sparkle:ignoreSkippedUpgradesBelowVersion";

NSString *const SURSSAttributeURL = @"url";
NSString *const SURSSAttributeLength = @"length";

NSString *const SURSSElementDescription = @"description";
NSString *const SURSSElementEnclosure = @"enclosure";
NSString *const SURSSElementLink = @"link";
NSString *const SURSSElementPubDate = @"pubDate";
NSString *const SURSSElementTitle = @"title";

NSString *const SUXMLLanguage = @"xml:lang";
