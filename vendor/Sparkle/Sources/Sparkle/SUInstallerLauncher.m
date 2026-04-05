//
//  SUInstallerLauncher.m
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerLauncher.h"
#import "SUInstallerLauncher+Private.h"
#import "SUFileManager.h"
#import "SULog.h"
#import "SPUMessageTypes.h"
#import "SPULocalCacheDirectory.h"
#import "SPUInstallationType.h"
#import "SUHost.h"
#import <ServiceManagement/ServiceManagement.h>
#import <SystemConfiguration/SystemConfiguration.h>

// We only fetch bundle icon for Installer Launcher XPC Service
#if defined(BUILDING_SPARKLE_SOURCES_EXTERNALLY) && BUILDING_SPARKLE_SOURCES_EXTERNALLY
#define FETCH_BUNDLE_ICON_FOR_AUTH 1
#else
#define FETCH_BUNDLE_ICON_FOR_AUTH 0
#endif

#if FETCH_BUNDLE_ICON_FOR_AUTH
#import <AppKit/AppKit.h>
#else
#include "AppKitPrevention.h"
#endif

@implementation SUInstallerLauncher

- (BOOL)submitProgressToolAtPath:(NSString *)progressToolPath withHostBundle:(NSBundle *)hostBundle inSystemDomainForInstaller:(BOOL)inSystemDomainForInstaller SPU_OBJC_DIRECT
{
    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    NSURL *progressToolURL = [NSURL fileURLWithPath:progressToolPath];
    
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:progressToolURL error:&quarantineError]) {
        // This may or may not be a fatal error depending on if the process is sandboxed or not
        SULog(SULogLevelError, @"Failed to release quarantine on installer at %@ with error %@", progressToolPath, quarantineError);
    }
    
    NSString *executablePath = [[NSBundle bundleWithURL:progressToolURL] executablePath];
    assert(executablePath != nil);
    
    NSString *hostBundlePath = hostBundle.bundlePath;
    assert(hostBundlePath != nil);
    
    NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    NSArray<NSString *> *arguments = @[executablePath, hostBundlePath, @(inSystemDomainForInstaller).stringValue];
    
    // The progress tool can only be ran as the logged in user, not as root
    CFStringRef domain = kSMDomainUserLaunchd;
    NSString *label = [NSString stringWithFormat:@"%@-sparkle-progress", hostBundleIdentifier];
    
    AuthorizationRef auth = NULL;
    Boolean submittedJob = false;
    OSStatus createStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (createStatus == errAuthorizationSuccess) {
        // Try to remove the job from launchd if it is already running
        // We could invoke SMJobCopyDictionary() first to see if the job exists, but I'd rather avoid
        // using it because the headers indicate it may be removed one day without any replacement
        CFErrorRef removeError = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!SMJobRemove(domain, (__bridge CFStringRef)(label), auth, true, &removeError)) {
#pragma clang diagnostic pop
            if (removeError != NULL) {
                // It's normal for a job to not be found, so this is not an interesting error
                if (CFErrorGetCode(removeError) != kSMErrorJobNotFound) {
                    SULog(SULogLevelError, @"Remove error: %@", removeError);
                }
                CFRelease(removeError);
            }
        }
        
        // If we are running as the root user, there is no need to explicitly set the UserName / GroupName keys
        // because we are submitting under the user domain, which should automatically use the the console user.
        NSMutableDictionary *jobDictionary = [[NSMutableDictionary alloc] init];
        jobDictionary[@"Label"] = label;
        jobDictionary[@"ProgramArguments"] = arguments;
        jobDictionary[@"EnableTransactions"] = @NO;
        jobDictionary[@"RunAtLoad"] = @YES;
        jobDictionary[@"Nice"] = @0;
        jobDictionary[@"ProcessType"] = @"Interactive";
        jobDictionary[@"LaunchOnlyOnce"] = @YES;
        jobDictionary[@"MachServices"] = @{SPUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES};
        
        CFErrorRef submitError = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // SMJobSubmit is deprecated but is the only way to submit a non-permanent
        // helper and allows us to submit to user domain without requiring authorization
        submittedJob = SMJobSubmit(domain, (__bridge CFDictionaryRef)(jobDictionary), auth, &submitError);
#pragma clang diagnostic pop
        if (!submittedJob) {
            if (submitError != NULL) {
                SULog(SULogLevelError, @"Submit progress error: %@", submitError);
                CFRelease(submitError);
            }
        }
        
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
    }
    
    return (submittedJob == true);
}

- (SUInstallerLauncherStatus)submitInstallerAtPath:(NSString *)installerPath withHostBundle:(NSBundle *)hostBundle iconBundlePath:(NSString *)iconBundlePath updaterIdentifier:(NSString *)updaterIdentifier userName:(NSString *)userName homeDirectory:(NSString *)homeDirectory mainBundleName:(NSString *)mainBundleName inSystemDomain:(BOOL)systemDomain rootUser:(BOOL)rootUser SPU_OBJC_DIRECT
{
    // No need to release the quarantine for this utility
    // In fact, we shouldn't because the tool may be located at a path we should not be writing too.
    
    NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    // The first argument has to be the path to the program, and the second is a host identifier so that the installer knows what mach services to host
    // The third and forth arguments are for home directory and user name which only pkg installer scripts may need
    // We intentionally do not pass any more arguments. Anything else should be done via IPC.
    // This is compatible to SMJobBless() which does not allow arguments
    // Even though we aren't using that function for now, it'd be wise to not decrease compatibility to it
    
    NSArray<NSString *> *arguments = @[installerPath, hostBundleIdentifier, homeDirectory, userName];
    
    AuthorizationRef auth = NULL;
    OSStatus createStatus = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth);
    if (createStatus != errAuthorizationSuccess) {
        auth = NULL;
        SULog(SULogLevelError, @"Failed to create authorization reference: %d", createStatus);
    }
    
    BOOL canceledAuthorization = NO;
    BOOL failedToUseSystemDomain = NO;
    if (auth != NULL && systemDomain && !rootUser) {
        // See Apple's 'EvenBetterAuthorizationSample' sample code and
        // https://developer.apple.com/library/mac/technotes/tn2095/_index.html#//apple_ref/doc/uid/DTS10003110-CH1-SECTION7
        // We can set a custom right name for authenticating as an administrator
        // Using this right rather than using something like kSMRightModifySystemDaemons allows us to present a better worded prompt
        // Note the right name is cached, so if we want to change the authorization
        // prompt, we may need to change the right name. I have found no good way around this :|
        
        SUHost *host = [[SUHost alloc] initWithBundle:hostBundle];
        NSString *hostName = host.name;
        
        // Figure out the authorization prompt and right name
        // We create the authorization prompt here so that a bad client cannot pass in a completely arbitrary prompt message
        // We also forgo localization for this prompt at the moment because with the right name being cached, updating localizations will be undesirable.
        // Furthermore, we can avoid adding localization files to the Installer XPC Service (if that one is being used).
        NSString *sparkleAuthTag = @"sparkle2-auth"; // this needs to change if auth wording changes
        NSString *rightNameString;
        NSString *authorizationPrompt;
        if ([hostBundleIdentifier isEqualToString:updaterIdentifier]) {
            // Application bundle is likely updating itself
            rightNameString = [NSString stringWithFormat:@"%@.%@", hostBundleIdentifier, sparkleAuthTag];
            authorizationPrompt = [NSString stringWithFormat:@"%1$@ wants permission to update.", hostName];
        } else {
            // Updater is likely updating a bundle that is not itself
            rightNameString = [NSString stringWithFormat:@"%@.%@.%@", updaterIdentifier, hostBundleIdentifier, sparkleAuthTag];
            authorizationPrompt = [NSString stringWithFormat:@"%1$@ wants permission to update %2$@.", mainBundleName, hostName];
        }
        
        const char *rightName = rightNameString.UTF8String;
        assert(rightName != NULL);
        
        OSStatus getRightResult = AuthorizationRightGet(rightName, NULL);
        if (getRightResult == errAuthorizationDenied) {
            if (AuthorizationRightSet(auth, rightName, (__bridge CFTypeRef _Nonnull)(@(kAuthorizationRuleAuthenticateAsAdmin)), (__bridge CFStringRef _Nullable)(authorizationPrompt), NULL, NULL) != errAuthorizationSuccess) {
                SULog(SULogLevelError, @"Failed to make auth right set");
            }
        }
        
        AuthorizationItem right = { .name = rightName, .valueLength = 0, .value = NULL, .flags = 0 };
        AuthorizationRights rights = { .count = 1, .items = &right };
        
        AuthorizationFlags flags = (AuthorizationFlags)(kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed);
        AuthorizationEnvironment authorizationEnvironment = {.count = 0, .items = NULL};
        
#if FETCH_BUNDLE_ICON_FOR_AUTH
        NSString *tempIconDestinationPath = nil;
        AuthorizationItem iconAuthorizationItem = {.name = kAuthorizationEnvironmentIcon, .valueLength = 0, .value = NULL, .flags = 0};
        char iconPathBuffer[] = "/tmp/XXXXXX.png";
        
        // If an icon bundle path is specified, write out a representation of the icon's data to a temporary file.
        // Then use that image data for the authorization prompt
        if (iconBundlePath != nil) {
            NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:iconBundlePath];
            
            // Creating a bitmap representation at a specific size is much cheaper than asking for icon's TIFFRepresentation
            // On older OS's we must create a 32x32 image otherwise it won't be scaled correctly in the dialog
            // On newer OS's we can use a slightly higher resolution image
            NSInteger imageDimensions;
            if (@available(macOS 10.15, *)) {
                imageDimensions = 64;
            } else {
                imageDimensions = 32;
            }
            
            NSBitmapImageRep *iconBitmapRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:imageDimensions pixelsHigh:imageDimensions bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            
            [NSGraphicsContext saveGraphicsState];
            
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:iconBitmapRep];
            [icon drawInRect:NSMakeRect(0.0, 0.0, (CGFloat)imageDimensions, (CGFloat)imageDimensions)];
            
            [NSGraphicsContext restoreGraphicsState];
            
            NSData *pngData = [iconBitmapRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            
            if (pngData != nil) {
                // Use /tmp rather than NSTemporaryDirectory() or SUFileManager's temp directory function because we want:
                // a) no spaces in the path (SU/NSFileManager fails here)
                // b) short file path that does not exceed a small threshold (NSTemporaryDirectory() fails here) only apply to older systems (eg: macOS 10.8)
                // The file also needs to be placed in a system readable place such as /tmp
                // See https://github.com/sparkle-project/Sparkle/issues/347#issuecomment-149523848 for more info
                int tempIconFile = mkstemps(iconPathBuffer, strlen(".png"));
                if (tempIconFile == -1) {
                    SULog(SULogLevelError, @"Failed to open temp icon from path buffer with error: %d", errno);
                } else {
                    close(tempIconFile);
                    
                    tempIconDestinationPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:iconPathBuffer length:strlen(iconPathBuffer)];
                    
                    if (tempIconDestinationPath != nil) {
                        if (![pngData writeToFile:tempIconDestinationPath atomically:NO]) {
                            SULog(SULogLevelError, @"Failed to write icon image data to %@", tempIconDestinationPath);
                        } else {
                            iconAuthorizationItem.valueLength = strlen(iconPathBuffer);
                            iconAuthorizationItem.value = iconPathBuffer;
                            
                            authorizationEnvironment.count = 1;
                            authorizationEnvironment.items = &iconAuthorizationItem;
                        }
                    }
                }
            }
        }
#endif
        
        // This should prompt up the authorization dialog if necessary
        OSStatus copyStatus = AuthorizationCopyRights(auth, &rights, &authorizationEnvironment, flags, NULL);
        if (copyStatus != errAuthorizationSuccess) {
            failedToUseSystemDomain = YES;
            
            if (copyStatus == errAuthorizationCanceled) {
                canceledAuthorization = YES;
            } else {
                SULog(SULogLevelError, @"Failed copying system domain rights: %d", copyStatus);
            }
        }
        
#if FETCH_BUNDLE_ICON_FOR_AUTH
        if (tempIconDestinationPath != nil) {
            [[NSFileManager defaultManager] removeItemAtPath:tempIconDestinationPath error:NULL];
        }
#endif
    }
    
    Boolean submittedJob = false;
    if (!canceledAuthorization && !failedToUseSystemDomain && auth != NULL) {
        CFStringRef domain = (systemDomain ? kSMDomainSystemLaunchd : kSMDomainUserLaunchd);
        NSString *label = [NSString stringWithFormat:@"%@-sparkle-updater", hostBundleIdentifier];
        
        // Try to remove the job from launchd if it is already running
        // We could invoke SMJobCopyDictionary() first to see if the job exists, but I'd rather avoid
        // using it because the headers indicate it may be removed one day without any replacement
        CFErrorRef removeError = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (!SMJobRemove(domain, (__bridge CFStringRef)(label), auth, true, &removeError)) {
#pragma clang diagnostic pop
            if (removeError != NULL) {
                // It's normal for a job to not be found, so this is not an interesting error
                if (CFErrorGetCode(removeError) != kSMErrorJobNotFound) {
                    SULog(SULogLevelError, @"Remove job error: %@", removeError);
                }
                CFRelease(removeError);
            }
        }
        
        NSDictionary *jobDictionary = @{@"Label" : label, @"ProgramArguments" : arguments, @"EnableTransactions" : @NO, @"RunAtLoad" : @YES, @"Nice" : @0, @"ProcessType": @"Interactive", @"LaunchOnlyOnce": @YES, @"MachServices" : @{SPUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES, SPUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) : @YES}};
        
        CFErrorRef submitError = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        // SMJobSubmit is deprecated but is the only way to submit a non-permanent
        // helper and allows us to submit to user domain without requiring authorization
        submittedJob = SMJobSubmit(domain, (__bridge CFDictionaryRef)(jobDictionary), auth, &submitError);
#pragma clang diagnostic pop
        if (!submittedJob) {
            if (submitError != NULL) {
                SULog(SULogLevelError, @"Submit error: %@", submitError);
                CFRelease(submitError);
            }
        }
    }
    
    if (auth != NULL) {
        AuthorizationFree(auth, kAuthorizationFlagDefaults);
    }
    
    SUInstallerLauncherStatus status;
    if (submittedJob == true) {
        status = SUInstallerLauncherSuccess;
    } else if (canceledAuthorization) {
        status = SUInstallerLauncherCanceled;
    } else {
        status = SUInstallerLauncherFailure;
    }
    return status;
}

- (NSString *)pathForBundledTool:(NSString *)toolName extension:(NSString *)extension fromBundle:(NSBundle *)bundle SPU_OBJC_DIRECT
{
    // If the path extension is empty, we don't want to add a "." at the end
    NSString *nameWithExtension = (extension.length > 0) ? [toolName stringByAppendingPathExtension:extension] : toolName;
    assert(nameWithExtension != nil);
    
    NSURL *auxiliaryToolURL;
    if ([bundle.bundleURL.pathExtension isEqualToString:@"xpc"]) {
        // Paranoid check to get full bundle URL
        NSURL *fullURL = bundle.bundleURL.URLByResolvingSymlinksInPath;
        
        auxiliaryToolURL = [fullURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent URLByAppendingPathComponent:nameWithExtension];
    } else {
        auxiliaryToolURL = [bundle URLForAuxiliaryExecutable:nameWithExtension];
    }
    
    if (auxiliaryToolURL == nil) {
        SULog(SULogLevelError, @"Error: Cannot retrieve path for auxiliary tool: %@", nameWithExtension);
        return nil;
    }
    
    NSURL *resolvedAuxiliaryToolURL = [auxiliaryToolURL URLByResolvingSymlinksInPath];
    if (resolvedAuxiliaryToolURL == nil) {
        SULog(SULogLevelError, @"Error: Cannot retrieve resolved path for auxiliary tool path: %@", auxiliaryToolURL.path);
        return nil;
    }
    
    return resolvedAuxiliaryToolURL.path;
}

BOOL SPUSystemNeedsAuthorizationAccessForBundlePath(NSString *bundlePath)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL hasWritability = [fileManager isWritableFileAtPath:bundlePath] && [fileManager isWritableFileAtPath:[bundlePath stringByDeletingLastPathComponent]];
    
    BOOL needsAuthorization;
    if (!hasWritability) {
        needsAuthorization = YES;
    } else {
        // Just because we have writability access does not mean we can set the correct owner/group
        // Test if we can set the owner/group on a temporarily created file
        // If we can, then we can probably perform an update without authorization
        
        NSString *tempFilename = @"permission_test" ;
        
        SUFileManager *suFileManager = [[SUFileManager alloc] init];
        NSURL *tempDirectoryURL = [suFileManager makeTemporaryDirectoryAppropriateForDirectoryURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:NULL];
        
        if (tempDirectoryURL == nil) {
            // I don't imagine this ever happening but in case it does, requesting authorization may be the better option
            needsAuthorization = YES;
        } else {
            NSURL *tempFileURL = [tempDirectoryURL URLByAppendingPathComponent:tempFilename];
            if (![[NSData data] writeToURL:tempFileURL atomically:NO]) {
                // Obvious indicator we may need authorization
                needsAuthorization = YES;
            } else {
                needsAuthorization = ![suFileManager changeOwnerAndGroupOfItemAtRootURL:tempFileURL toMatchURL:[NSURL fileURLWithPath:bundlePath] error:NULL];
            }
            
            [suFileManager removeItemAtURL:tempDirectoryURL error:NULL];
        }
    }
    
    return needsAuthorization;
}

static BOOL SPUUsesSystemDomainForBundlePath(NSString *path, BOOL rootUser
#if SPARKLE_BUILD_PACKAGE_SUPPORT
                                             , NSString *installationType
#endif
)
{
    if (!rootUser) {
#if SPARKLE_BUILD_PACKAGE_SUPPORT
        if ([installationType isEqualToString:SPUInstallationTypeGuidedPackage]) {
            return YES;
        } else
#endif
        {
            return SPUSystemNeedsAuthorizationAccessForBundlePath(path);
        }
    } else {
        // If we are the root user we use the system domain even if we don't need escalated authorization.
        // Note interactive package installations are not supported as root.
        return YES;
    }
}

// Note: do not pass information which can we compute ourselves here, such as paths to the installer and progress agent tools
- (void)launchInstallerWithHostBundlePath:(NSString *)hostBundlePath mainBundlePath:(NSString *)mainBundlePath installationType:(NSString *)installationType allowingDriverInteraction:(BOOL)allowingDriverInteraction completion:(void (^)(SUInstallerLauncherStatus, BOOL))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (completionHandler == NULL) {
            SULog(SULogLevelError, @"Error: Failed to retrieve completionHandler (nil)");
            return;
        }
        
        if (hostBundlePath == nil) {
            SULog(SULogLevelError, @"Error: Failed to retrieve hostBundlePath (nil)");
            completionHandler(SUInstallerLauncherFailure, NO);
            return;
        }
        
        if (mainBundlePath == nil) {
            SULog(SULogLevelError, @"Error: Failed to retrieve mainBundlePath (nil)");
            completionHandler(SUInstallerLauncherFailure, NO);
            return;
        }
        
        NSBundle *mainBundle = [NSBundle bundleWithPath:mainBundlePath];
        if (mainBundle == nil) {
            SULog(SULogLevelError, @"Error: Failed to retrieve mainBundle from path: %@", mainBundlePath);
            completionHandler(SUInstallerLauncherFailure, NO);
            return;
        }
        
        SUHost *mainBundleHost = [[SUHost alloc] initWithBundle:mainBundle];
        
        // We use SUHost.name property, so an application
        // or Sparkle helper application can override its name with SUBundleName key
        NSString *mainBundleName = mainBundleHost.name;
        
        // This updaterIdentifier is just used for authorization prompt
        NSString *updaterIdentifier;
        NSString *mainBundleIdentifier = mainBundle.bundleIdentifier;
        if (mainBundleIdentifier != nil) {
            updaterIdentifier = mainBundleIdentifier;
        } else {
            // Should be unlikely
            updaterIdentifier = mainBundleHost.name;
        }
        
        if (installationType == nil) {
            SULog(SULogLevelError, @"Error: Failed to retrieve installationType (nil)");
            completionHandler(SUInstallerLauncherFailure, NO);
            return;
        }
        
        // We could do a sort of preflight Authorization test instead of testing if we are running as root,
        // but I think this is not necessarily a better approach. We have to chown() the launcher cache directory later on,
        // and that is not necessarily related to a preflight test. It's more related to being ran under a root / different user from the active GUI session
        BOOL rootUser = (geteuid() == 0);
        
        BOOL inSystemDomain = SPUUsesSystemDomainForBundlePath(hostBundlePath, rootUser
#if SPARKLE_BUILD_PACKAGE_SUPPORT
                                                               , installationType
#endif
                                                               );
        
        NSBundle *hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        if (hostBundle == nil) {
            SULog(SULogLevelError, @"InstallerLauncher failed to create bundle at %@", hostBundlePath);
            SULog(SULogLevelError, @"Please make sure InstallerLauncher is not sandboxed and do not sign your app by passing --deep. Check: codesign -d --entitlements :- \"%@\"", NSBundle.mainBundle.bundlePath);
            SULog(SULogLevelError, @"More information regarding sandboxing: https://sparkle-project.org/documentation/sandboxing/");
            completionHandler(SUInstallerLauncherFailure, inSystemDomain);
            return;
        }
        
        // if we need to use the system authorization from non-root and we aren't allowed interaction, then try sometime later when interaction is allowed
        if (inSystemDomain && !rootUser && !allowingDriverInteraction) {
            completionHandler(SUInstallerLauncherAuthorizeLater, inSystemDomain);
            return;
        }
        
        NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
        assert(hostBundleIdentifier != nil);
        
        // We could be inside the InstallerLauncher XPC bundle or in the Sparkle.framework bundle if no XPC service is used
        NSBundle *ourBundle = [NSBundle bundleForClass:[self class]];
        
        // Note we do not have to copy this tool out of the bundle it's in because it's a utility with no dependencies.
        // Furthermore, we can keep the tool at a place that may not necessarily be writable.
        NSString *installerPath = [self pathForBundledTool:@""SPARKLE_RELAUNCH_TOOL_NAME extension:@"" fromBundle:ourBundle];
        if (installerPath == nil) {
            SULog(SULogLevelError, @"Error: Cannot submit installer because the installer could not be located");
            completionHandler(SUInstallerLauncherFailure, inSystemDomain);
            return;
        }
        
        // We do however have to copy the progress tool app somewhere safe due to its external dependencies
        NSString *progressToolResourcePath = [self pathForBundledTool:@""SPARKLE_INSTALLER_PROGRESS_TOOL_NAME extension:@"app" fromBundle:ourBundle];
        
        if (progressToolResourcePath == nil) {
            SULog(SULogLevelError, @"Error: Cannot submit progress tool because the progress tool could not be located");
            completionHandler(SUInstallerLauncherFailure, inSystemDomain);
            return;
        }
        
        NSString *userName;
        NSString *homeDirectory;
        uid_t uid = 0;
        gid_t gid = 0;
        if (!rootUser) {
            // Normal path
            homeDirectory = NSHomeDirectory();
            assert(homeDirectory != nil);
            
            userName = NSUserName();
            assert(userName != nil);
        } else {
            // As the root user we need to obtain the user name and home directory reflecting
            // the user's console session.
            CFStringRef userNameRef = SCDynamicStoreCopyConsoleUser(NULL, &uid, &gid);
            if (userNameRef == NULL) {
                SULog(SULogLevelError, @"Failed to retrieve user name from the console user");
                completionHandler(SUInstallerLauncherFailure, inSystemDomain);
                return;
            }
            
            userName = (NSString *)CFBridgingRelease(userNameRef);
            homeDirectory = NSHomeDirectoryForUser(userName);
            if (homeDirectory == nil) {
                SULog(SULogLevelError, @"Failed to retrieve home directory for user: %@", userName);
                
                completionHandler(SUInstallerLauncherFailure, inSystemDomain);
                return;
            }
        }
        
        // It may be tempting here to validate/match the signature of the installer and progress tool, however this is not very reliable
        // We can't compare the signature of this framework/XPC service (depending how it's run) to the host bundle because
        // they could be different (eg: take a look at sparkle-cli). We also can't easily tell if the signature of the service/framework is the same as the bundle it's inside.
        // The service/framework also need not even be signed in the first place. We'll just assume for now the original bundle hasn't been tampered with
        NSString *cachePath = rootUser ?
            [SPULocalCacheDirectory cachePathForBundleIdentifier:hostBundleIdentifier userName:userName] :
            [SPULocalCacheDirectory cachePathForBundleIdentifier:hostBundleIdentifier];
        
        NSString *rootLauncherCachePath = [cachePath stringByAppendingPathComponent:@"Launcher"];
        
        [SPULocalCacheDirectory removeOldItemsInDirectory:rootLauncherCachePath];
        
        NSDictionary<NSFileAttributeKey, id> *fileAttributes = rootUser ?
            @{NSFileOwnerAccountID: @(uid), NSFileGroupOwnerAccountID: @(gid)} :
            nil;
        
        NSString *launcherCachePath = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:rootLauncherCachePath intermediateDirectoryFileAttributes:fileAttributes];
        
        if (launcherCachePath == nil) {
            SULog(SULogLevelError, @"Failed to create cache directory for progress tool in %@", rootLauncherCachePath);
            completionHandler(SUInstallerLauncherFailure, inSystemDomain);
            return;
        }
        
        SUFileManager *fileManager = [[SUFileManager alloc] init];
        
        if (rootUser) {
            // Ensure the console user has ownership of the launcher cache directory
            // Otherwise the updater may not launch and not be able to clean up itself
            NSError *changeOwnerAndGroupError = nil;
            if (![fileManager changeOwnerAndGroupOfItemAtURL:[NSURL fileURLWithPath:launcherCachePath] ownerID:uid groupID:gid error:&changeOwnerAndGroupError]) {
                SULog(SULogLevelError, @"Failed to change owner and group for launcher cache directory: %@", changeOwnerAndGroupError);
                
                completionHandler(SUInstallerLauncherFailure, inSystemDomain);
                return;
            }
        }
        
        NSString *progressToolPath = [launcherCachePath stringByAppendingPathComponent:@""SPARKLE_INSTALLER_PROGRESS_TOOL_NAME@".app"];
        
        NSError *copyError = nil;
        // SUFileManager is more reliable for copying files around
        if (![fileManager copyItemAtURL:[NSURL fileURLWithPath:progressToolResourcePath] toURL:[NSURL fileURLWithPath:progressToolPath] error:&copyError]) {
            SULog(SULogLevelError, @"Failed to copy progress tool to cache: %@", copyError);
            completionHandler(SUInstallerLauncherFailure, inSystemDomain);
            return;
        }
        
        SUInstallerLauncherStatus installerStatus = [self submitInstallerAtPath:installerPath withHostBundle:hostBundle iconBundlePath:mainBundle.bundlePath updaterIdentifier:updaterIdentifier userName:userName homeDirectory:homeDirectory mainBundleName:mainBundleName inSystemDomain:inSystemDomain rootUser:rootUser];
        
        BOOL submittedProgressTool = NO;
        if (installerStatus == SUInstallerLauncherSuccess) {
            submittedProgressTool = [self submitProgressToolAtPath:progressToolPath withHostBundle:hostBundle inSystemDomainForInstaller:inSystemDomain];
            
            if (!submittedProgressTool) {
                SULog(SULogLevelError, @"Failed to submit progress tool job");
            }
        } else if (installerStatus == SUInstallerLauncherFailure) {
            SULog(SULogLevelError, @"Failed to submit installer job");
            SULog(SULogLevelError, @"If your application is sandboxed please follow steps at: https://sparkle-project.org/documentation/sandboxing/");
        }
        
        if (installerStatus == SUInstallerLauncherCanceled) {
            completionHandler(installerStatus, inSystemDomain);
        } else {
            completionHandler(submittedProgressTool ? SUInstallerLauncherSuccess : SUInstallerLauncherFailure, inSystemDomain);
        }
    });
}

@end
