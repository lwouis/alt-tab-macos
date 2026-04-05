//
//  SUUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#if SPARKLE_BUILD_UI_BITS

#import "SUUpdateAlert.h"

#import "SUHost.h"
#import "SUReleaseNotesView.h"
#import "SUWKWebView.h"
#import "SULegacyWebView.h"
#import "SUTextViewReleaseNotesView.h"

#import "SUConstants.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUAppcastItem.h"
#import "SPUDownloadData.h"
#import "SUApplicationInfo.h"
#import "SPUUpdaterSettings.h"
#import "SUTouchBarButtonGroup.h"
#import "SPUXPCServiceInfo.h"
#import "SPUUserUpdateState.h"

static NSString *const SUUpdateAlertTouchBarIdentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdateAlert";
static NSString *const SUAllowsAutomaticUpdatesKeyPath = @"allowsAutomaticUpdates";

static const CGFloat SUUpdateAlertGroupElementSpacing = 12.0;

typedef NS_ENUM(NSInteger, SUReleaseNotesFormat)
{
    SUReleaseNotesFormatHTML,
    SUReleaseNotesFormatPlainText,
    SUReleaseNotesFormatMarkdown
};

@interface SUUpdateAlert () <NSTouchBarDelegate>
@end

@implementation SUUpdateAlert
{
    SPUUpdaterSettings *_updaterSettings;
    SUAppcastItem *_updateItem;
    SUHost *_host;
    SPUUserUpdateState *_state;
    NSProgressIndicator *_releaseNotesSpinner;
    id<SUReleaseNotesView> _releaseNotesView;
    id<SUVersionDisplay> _versionDisplayer;
    
    __weak id<SPUStandardUserDriverDelegate> _delegate;
    
    IBOutlet NSStackView *_stackView;
    IBOutlet NSButton *_installButton;
    IBOutlet NSButton *_laterButton;
    IBOutlet NSButton *_skipButton;
    IBOutlet NSBox *_releaseNotesBoxView;
    IBOutlet NSView *_releaseNotesContentView;
    IBOutlet NSButton *_automaticallyInstallUpdatesButton;
    IBOutlet NSView *_titleView;
    
    void (^_didBecomeKeyBlock)(void);
    void(^_completionBlock)(SPUUserUpdateChoice, NSRect, BOOL);
    
    BOOL _windowLoadedAndShowsReleaseNotes;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state host:(SUHost *)aHost versionDisplayer:(id<SUVersionDisplay>)versionDisplayer updaterSettings:(SPUUpdaterSettings *)updaterSettings delegate:(id<SPUStandardUserDriverDelegate>)delegate completionBlock:(void (^)(SPUUserUpdateChoice, NSRect, BOOL))completionBlock didBecomeKeyBlock:(void (^)(void))didBecomeKeyBlock
{
    self = [super initWithWindowNibName:@"SUUpdateAlert"];
    if (self != nil) {
        _host = aHost;
        _updateItem = item;
        _versionDisplayer = versionDisplayer;
        
        _state = state;
        _delegate = delegate;
        _completionBlock = [completionBlock copy];
        _didBecomeKeyBlock = [didBecomeKeyBlock copy];
        
        _updaterSettings = updaterSettings;
        
        [self setShouldCascadeWindows:NO];
    } else {
        assert(false);
    }
    return self;
}

- (void)dealloc
{
    if (self.windowLoaded) {
        [_updaterSettings removeObserver:self forKeyPath:SUAllowsAutomaticUpdatesKeyPath];
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath];
}

- (void)setInstallButtonFocus:(BOOL)focus
{
    if (focus) {
        _installButton.keyEquivalent = @"\r";
    } else {
        _installButton.keyEquivalent = @"";
    }
}

- (void)endWithSelection:(SPUUserUpdateChoice)choice SPU_OBJC_DIRECT
{
    [_releaseNotesView stopLoading];
    [_releaseNotesView.view removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
    
    NSWindow *window = self.window;
    BOOL wasKeyWindow = window.keyWindow;
    NSRect windowFrame = window.frame;
    
    [self close];
    
    if (_completionBlock != nil) {
        _completionBlock(choice, windowFrame, wasKeyWindow);
        _completionBlock = nil;
    }
}

- (IBAction)installUpdate:(id)__unused sender
{
    [self endWithSelection:SPUUserUpdateChoiceInstall];
}

- (IBAction)openInfoURL:(id)__unused sender
{
    NSURL *infoURL = _updateItem.infoURL;
    assert(infoURL);
    
    [[NSWorkspace sharedWorkspace] openURL:infoURL];
    
    [self endWithSelection:SPUUserUpdateChoiceDismiss];
}

- (IBAction)skipThisVersion:(id)__unused sender
{
    [self endWithSelection:SPUUserUpdateChoiceSkip];
}

- (IBAction)remindMeLater:(id)__unused sender
{
    [self endWithSelection:SPUUserUpdateChoiceDismiss];
}

- (void)displayReleaseNotesSpinner SPU_OBJC_DIRECT
{
    // Stick a nice big spinner in the middle of the release notes view until the page is loaded.
    _releaseNotesSpinner = [[NSProgressIndicator alloc] init];
    _releaseNotesSpinner.controlSize = NSControlSizeRegular;
    [_releaseNotesSpinner setStyle:NSProgressIndicatorStyleSpinning];
    
    [_releaseNotesContentView addSubview:_releaseNotesSpinner];
    
    _releaseNotesSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_releaseNotesSpinner.centerXAnchor constraintEqualToAnchor:_releaseNotesContentView.centerXAnchor],
        [_releaseNotesSpinner.centerYAnchor constraintEqualToAnchor:_releaseNotesContentView.centerYAnchor]
    ]];
    
    _releaseNotesSpinner.displayedWhenStopped = NO;
    [_releaseNotesSpinner startAnimation:self];
    
    // If there's no release notes URL, just stick the contents of the description into the release notes view
    // Otherwise we'll wait until the client wants us to show release notes
    if (_updateItem.releaseNotesURL == nil) {
        NSString *itemDescription = _updateItem.itemDescription;
        if (itemDescription != nil) {
            NSString *itemDescriptionFormat = _updateItem.itemDescriptionFormat;
            
            SUReleaseNotesFormat releaseNotesFormat;
            if ([itemDescriptionFormat isEqualToString:@"plain-text"]) {
                releaseNotesFormat = SUReleaseNotesFormatPlainText;
            } else if ([itemDescriptionFormat isEqualToString:@"markdown"]) {
                releaseNotesFormat = SUReleaseNotesFormatMarkdown;
            } else {
                releaseNotesFormat = SUReleaseNotesFormatHTML;
            }
            
            [self _createReleaseNotesViewPreferringFormat:releaseNotesFormat];
            
            __weak __typeof__(self) weakSelf = self;
            [_releaseNotesView loadString:itemDescription baseURL:nil completionHandler:^(NSError * _Nullable error) {
                if (error != nil) {
                    SULog(SULogLevelError, @"Failed to load HTML string from release notes view: %@", error);
                }
                [weakSelf stopReleaseNotesSpinner];
            }];
        }
    }
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    if (!_windowLoadedAndShowsReleaseNotes) {
        if (self.window == nil) {
            // Window was not properly loaded.
            // This can happen if the app moves and the update alert nib fails to load
            // This puts Sparkle in an unsupported state but we will try to avoid crashing
            SULog(SULogLevelError, @"Error: SUUpdateAlert window is nil and failed to load, which may mean the app was moved. Sparkle is running in an unsupported state.");
        } else if ([_host.bundle isEqual:NSBundle.mainBundle]) {
            SULog(SULogLevelError, @"Warning: '%@' is configured to not show release notes but release notes for version %@ were downloaded. Consider either removing release notes from your appcast or implementing -[SPUUpdaterDelegate updater:shouldDownloadReleaseNotesForUpdate:]", _host.name, _updateItem.displayVersionString);
        }
        return;
    }
    
    NSURL *releaseNotesURL = _updateItem.releaseNotesURL;
    NSURL *baseURL = releaseNotesURL.URLByDeletingLastPathComponent;
    // If a MIME type isn't provided, we will pick html as the default, as opposed to plain text. Questionable decision..
    NSString *chosenMIMEType = (downloadData.MIMEType != nil) ? downloadData.MIMEType : @"text/html";
    // We'll pick utf-8 as the default text encoding name if one isn't provided which I think is reasonable
    NSString *chosenTextEncodingName = (downloadData.textEncodingName != nil) ? downloadData.textEncodingName : @"utf-8";
    
    // We don't support markdown but prepare for the future in case we support it one day
    NSString *pathExtension = releaseNotesURL.pathExtension;
    
    SUReleaseNotesFormat releaseNotesFormat;
    // Make sure we test for markdown first because text/plain may be used for MIME type
    if ([chosenMIMEType isEqualToString:@"text/markdown"] ||
               [chosenMIMEType isEqualToString:@"text/x-markdown"] ||
               [pathExtension caseInsensitiveCompare:@"md"] == NSOrderedSame ||
               [pathExtension caseInsensitiveCompare:@"markdown"] == NSOrderedSame) {
        releaseNotesFormat = SUReleaseNotesFormatMarkdown;
    } else if ([chosenMIMEType isEqualToString:@"text/plain"] || [pathExtension caseInsensitiveCompare:@"txt"] == NSOrderedSame) {
        releaseNotesFormat = SUReleaseNotesFormatPlainText;
    } else {
        releaseNotesFormat = SUReleaseNotesFormatHTML;
    }
    
    [self _createReleaseNotesViewPreferringFormat:releaseNotesFormat];
    
    __weak __typeof__(self) weakSelf = self;
    [_releaseNotesView loadData:downloadData.data MIMEType:chosenMIMEType textEncodingName:chosenTextEncodingName baseURL:baseURL completionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            SULog(SULogLevelError, @"Failed to load data from release notes view: %@", error);
        }
        [weakSelf stopReleaseNotesSpinner];
    }];
}

- (void)showReleaseNotesFailedToDownloadWithError:(NSError *)error
{
    [self _createReleaseNotesViewPreferringFormat:SUReleaseNotesFormatPlainText];
    
    __weak __typeof__(self) weakSelf = self;
    [_releaseNotesView loadString:error.localizedDescription baseURL:nil completionHandler:^(NSError * _Nullable loadCompletionError) {
        if (loadCompletionError != nil) {
            SULog(SULogLevelError, @"Failed to load HTML error string from release notes view: %@", loadCompletionError);
        }
        
        [weakSelf stopReleaseNotesSpinner];
    }];
}

- (void)stopReleaseNotesSpinner SPU_OBJC_DIRECT
{
    [_releaseNotesSpinner stopAnimation:self];
}

- (BOOL)showsReleaseNotes
{
    NSNumber *shouldShowReleaseNotes = [_host boolNumberForInfoDictionaryKey:SUShowReleaseNotesKey];
    if (shouldShowReleaseNotes == nil) {
        // Don't show release notes if RSS item contains no description and no release notes URL:
        return (([_updateItem itemDescription] != nil
                 && [[[_updateItem itemDescription] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0)
                || [_updateItem releaseNotesURL] != nil);
    }
    else
        return [shouldShowReleaseNotes boolValue];
}

- (void)_createReleaseNotesViewPreferringFormat:(SUReleaseNotesFormat)preferredReleaseNotesFormat SPU_OBJC_DIRECT
{
    // "-apple-system-font" is a reference to the system UI font. "-apple-system" is the new recommended token, but for backward compatibility we can't use it.
    NSString *defaultFontFamily = @"-apple-system-font";
    
    int defaultFontSize = (int)[NSFont systemFontSize];
    
    SUReleaseNotesFormat usedReleaseNotesFormat;
    switch (preferredReleaseNotesFormat) {
        case SUReleaseNotesFormatPlainText:
        case SUReleaseNotesFormatMarkdown:
            usedReleaseNotesFormat = preferredReleaseNotesFormat;
            break;
        case SUReleaseNotesFormatHTML:
            if (@available(macOS 10.15, *)) {
                if ([[NSProcessInfo processInfo] isMacCatalystApp]) {
                    usedReleaseNotesFormat = SUReleaseNotesFormatPlainText;
                    
                    SULog(SULogLevelError, @"Error: Showing HTML release notes for Catalyst apps is not supported. The release notes will be interpreted as plain text. Please serve a plain-text (.txt) or markdown (.md) release notes file. If you are using a <description> element then please specify the %@=\"plain-text\" or %@=\"markdown\" attribute in that element.", SUAppcastAttributeFormat, SUAppcastAttributeFormat);
                } else {
                    usedReleaseNotesFormat = preferredReleaseNotesFormat;
                }
            } else {
                usedReleaseNotesFormat = preferredReleaseNotesFormat;
            }
            break;
    }
    
    NSArray<NSString *> *customAllowedURLSchemes;
    {
        NSMutableArray<NSString *> *allowedSchemes = [NSMutableArray array];
        NSArray *hostAllowedURLSchemes = [_host objectForInfoDictionaryKey:SUAllowedURLSchemesKey ofClass:NSArray.class];
        if (hostAllowedURLSchemes != nil) {
            for (id urlScheme in hostAllowedURLSchemes) {
                if ([(NSObject *)urlScheme isKindOfClass:[NSString class]]) {
                    NSString *allowedURLScheme = [(NSString *)urlScheme lowercaseString];
                    if (![allowedURLScheme isEqualToString:@"file"]) {
                        [allowedSchemes addObject:allowedURLScheme];
                    } else {
                        SULog(SULogLevelError, @"Error: Found 'file' scheme in %@. Ignoring because this scheme is unsafe.", SUAllowedURLSchemesKey);
                    }
                }
            }
        }
        
        customAllowedURLSchemes = [allowedSchemes copy];
    }
    
    id<SPUStandardUserDriverDelegate> delegate = _delegate;
    switch (usedReleaseNotesFormat) {
        case SUReleaseNotesFormatPlainText:
            _releaseNotesView = [[SUTextViewReleaseNotesView alloc] initWithFontPointSize:defaultFontSize appcastItem:_updateItem host:_host delegate:delegate prefersMarkdown:NO customAllowedURLSchemes:customAllowedURLSchemes];
            break;
        case SUReleaseNotesFormatMarkdown:
            _releaseNotesView = [[SUTextViewReleaseNotesView alloc] initWithFontPointSize:defaultFontSize appcastItem:_updateItem host:_host delegate:delegate prefersMarkdown:YES customAllowedURLSchemes:customAllowedURLSchemes];
            break;
        case SUReleaseNotesFormatHTML:
        {
            NSURL *colorStyleURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"ReleaseNotesColorStyle" withExtension:@"css"];
            
            BOOL javaScriptEnabled = [_host boolForInfoDictionaryKey:SUEnableJavaScriptKey];
            
#if DOWNLOADER_XPC_SERVICE_EMBEDDED
            // WKWebView has a bug where it won't work in loading local HTML content in sandboxed apps that do not have an outgoing network entitlement
            // FB6993802: https://twitter.com/sindresorhus/status/1160577243929878528 | https://github.com/feedback-assistant/reports/issues/1
            // If the developer is using the downloader XPC service, they are very most likely are a) sandboxed b) do not use outgoing network entitlement.
            // In this case, fall back to legacy WebKit view.
            // (In theory it is possible for a non-sandboxed app or sandboxed app with outgoing network entitlement to use the XPC service, it's just unlikely and unsupported).
            // Note: because legacy web view is only supported with using downloader XPC Service, and the app
            // should not have an outgoing network client, there's no need to be concerned about the
            // appcast signing validation status for loading external resources, which shouldn't be possible.
            BOOL useWKWebView = !SPUXPCServiceIsEnabled(SUEnableDownloaderServiceKey);
            if (!useWKWebView) {
                _releaseNotesView = [[SULegacyWebView alloc] initWithColorStyleSheetLocation:colorStyleURL fontFamily:defaultFontFamily fontPointSize:defaultFontSize javaScriptEnabled:javaScriptEnabled customAllowedURLSchemes:customAllowedURLSchemes];
            } else
#endif
            {
                BOOL allowsLoadingExternalReferences = (_updateItem.signingValidationStatus == SPUAppcastSigningValidationStatusSkipped);
                
                _releaseNotesView = [[SUWKWebView alloc] initWithColorStyleSheetLocation:colorStyleURL fontFamily:defaultFontFamily fontPointSize:defaultFontSize javaScriptEnabled:javaScriptEnabled customAllowedURLSchemes:customAllowedURLSchemes allowsLoadingExternalReferences:allowsLoadingExternalReferences installedVersion:_host.version];
            }
            
            break;
        }
    }
    
    assert(_releaseNotesSpinner != nil);
    [_releaseNotesContentView addSubview:_releaseNotesView.view positioned:NSWindowBelow relativeTo:_releaseNotesSpinner];
    
    _releaseNotesView.view.frame = _releaseNotesContentView.bounds;
    _releaseNotesView.view.autoresizingMask = (NSAutoresizingMaskOptions)(NSViewWidthSizable | NSViewHeightSizable);
    
    if (@available(macOS 10.14, *)) {
        // We need a transparent background
        // This avoids a "white flash" that may be present when the webview initially loads in dark mode
        // This also is necessary for macOS 10.14, otherwise the background may stay white on 10.14 (but not in later OS's)
        [_releaseNotesView setDrawsBackground:NO];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:SUAllowsAutomaticUpdatesKeyPath]) {
        _automaticallyInstallUpdatesButton.superview.hidden = !_updaterSettings.allowsAutomaticUpdates;
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)windowDidLoad
{
    NSWindow *window = self.window;
    
    window.movableByWindowBackground = YES;
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    [_stackView setCustomSpacing:SUUpdateAlertGroupElementSpacing afterView:_titleView];
    
    // Customize custom NSBox
    {
        CGFloat boxCornerRadius = 6.0;
        CGFloat boxBorderWidth = 1.0;
        
        _releaseNotesBoxView.boxType = NSBoxCustom;
        _releaseNotesBoxView.cornerRadius = boxCornerRadius;
        if (@available(macOS 10.14, *)) {
            _releaseNotesBoxView.borderColor = NSColor.separatorColor;
        } else {
            _releaseNotesBoxView.borderColor = [NSColor colorWithCalibratedWhite:0.84 alpha:1.0];
        }
        _releaseNotesBoxView.borderWidth = boxBorderWidth;
        _releaseNotesBoxView.fillColor = NSColor.textBackgroundColor;
        
        // Needed so we don't clip the corners if the CSS uses a custom background
        _releaseNotesBoxView.contentView.wantsLayer = YES;
        _releaseNotesBoxView.contentView.layer.masksToBounds = YES;
        _releaseNotesBoxView.contentView.layer.cornerRadius = boxCornerRadius - boxBorderWidth;
    }
    
    _laterButton.title = SULocalizedStringFromTableInBundle(@"Remind Me Later", SPARKLE_TABLE, sparkleBundle, @"");
    _skipButton.title = SULocalizedStringFromTableInBundle(@"Skip This Version", SPARKLE_TABLE, sparkleBundle, @"");
    _installButton.title = SULocalizedStringFromTableInBundle(@"Install Update", SPARKLE_TABLE, sparkleBundle, @"");
    _automaticallyInstallUpdatesButton.title = SULocalizedStringFromTableInBundle(@"Automatically download and install updates in the future", SPARKLE_TABLE, sparkleBundle, @"");
    
    if (@available(macOS 16, *)) {
        _skipButton.controlSize = NSControlSizeLarge;
        _laterButton.controlSize = NSControlSizeLarge;
        _installButton.controlSize = NSControlSizeLarge;
    }
    
    BOOL showReleaseNotes = [self showsReleaseNotes];
    if (showReleaseNotes) {
        window.frameAutosaveName = @"SUUpdateAlert2";
    } else {
        // Update alert should not be resizable when no release notes are available
        window.styleMask = (NSWindowStyleMask)(window.styleMask & ~NSWindowStyleMaskResizable);
    }
    _windowLoadedAndShowsReleaseNotes = showReleaseNotes;

    if (_updateItem.informationOnlyUpdate) {
        [_installButton setTitle:SULocalizedStringFromTableInBundle(@"Learn More…", SPARKLE_TABLE, sparkleBundle, @"Alternate title for 'Install Update' button when there's no download in RSS feed.")];
        [_installButton setAction:@selector(openInfoURL:)];
    }
    
    if (showReleaseNotes) {
        [self displayReleaseNotesSpinner];
        
        // Add more spacing to give choices and automatic installs checkbox better grouping
        [_stackView setCustomSpacing:SUUpdateAlertGroupElementSpacing afterView:_releaseNotesBoxView];
    } else {
        _releaseNotesBoxView.hidden = YES;
    }
    
    // NOTE: The code below for deciding what buttons to hide is complex! Due to array of feature configurations :)
    
    [_updaterSettings addObserver:self forKeyPath:SUAllowsAutomaticUpdatesKeyPath options:(NSKeyValueObservingOptions)(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew) context:NULL];
    
    if (_state.stage == SPUUserUpdateStageInstalling) {
        // We're going to be relaunching pretty instantaneously
        _installButton.title = SULocalizedStringFromTableInBundle(@"Install and Relaunch", SPARKLE_TABLE, sparkleBundle, nil);
        
        // We should be explicit that the update will be installed on quit
        _laterButton.title = SULocalizedStringFromTableInBundle(@"Install on Quit", SPARKLE_TABLE, sparkleBundle, @"Alternate title for 'Remind Me Later' button when downloaded updates can be resumed");
    }

    if (_updateItem.criticalUpdate && !_updateItem.majorUpgrade) {
        _skipButton.hidden = YES;
        _laterButton.hidden = YES;
    }
    
    // Reminding user later doesn't make sense when automatic update checks are off
    if (![_host boolForKey:SUEnableAutomaticChecksKey]) {
        _laterButton.hidden = YES;
    }

    [window center];
}

- (void)windowDidBecomeKey:(NSNotification *)__unused note
{
    if (_didBecomeKeyBlock != NULL) {
        _didBecomeKeyBlock();
    }
}

- (BOOL)windowShouldClose:(NSNotification *) __unused note
{
    [self endWithSelection:SPUUserUpdateChoiceDismiss];
    return YES;
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:_host];
}

- (NSString *)titleText
{
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    if (_updateItem.criticalUpdate)
    {
        return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"An important update to %@ is ready to install", SPARKLE_TABLE, sparkleBundle, nil), _host.name];
    }
    else if (_state.stage == SPUUserUpdateStageDownloaded || _state.stage == SPUUserUpdateStageInstalling)
    {
        return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"A new version of %@ is ready to install!", SPARKLE_TABLE, sparkleBundle, nil), _host.name];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"A new version of %@ is available!", SPARKLE_TABLE, sparkleBundle, nil), _host.name];
    }
}

- (NSString *)descriptionText
{
    NSString *updateItemDisplayVersion = [_updateItem displayVersionString];
    NSString *hostDisplayVersion = [_host displayVersion];
    
    if ([_versionDisplayer respondsToSelector:@selector(formatUpdateDisplayVersionFromUpdate:andBundleDisplayVersion:withBundleVersion:)]) {
        updateItemDisplayVersion = [_versionDisplayer formatUpdateDisplayVersionFromUpdate:_updateItem andBundleDisplayVersion:&hostDisplayVersion withBundleVersion:_host.version];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_versionDisplayer formatVersion:&updateItemDisplayVersion andVersion:&hostDisplayVersion];
#pragma clang diagnostic pop
    }

    // We display a different summary depending on if it's an "info-only" item, or a "critical update" item, or if we've already downloaded the update and just need to relaunch
    NSString *finalString = nil;

#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    if (_updateItem.informationOnlyUpdate) {
        finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is now available—you have %@. Would you like to learn more about this update on the web?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the update informational with no download."), _host.name, updateItemDisplayVersion, hostDisplayVersion];
    } else if (_updateItem.criticalUpdate) {
        if (_state.stage == SPUUserUpdateStageNotDownloaded) {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is now available—you have %@. This is an important update; would you like to download it now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the critical update is downloadable."), _host.name, updateItemDisplayVersion, hostDisplayVersion];
        } else {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the critical update has already been downloaded and ready to install."), _host.name, updateItemDisplayVersion];
        }
    } else {
        if (_state.stage == SPUUserUpdateStageNotDownloaded) {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is now available—you have %@. Would you like to download it now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the update is downloadable."), _host.name, updateItemDisplayVersion, hostDisplayVersion];
        } else {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the update has already been downloaded and ready to install."), _host.name, updateItemDisplayVersion];
        }
    }
    return finalString;
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdateAlertTouchBarIdentifier,];
    touchBar.principalItemIdentifier = SUUpdateAlertTouchBarIdentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUUpdateAlertTouchBarIdentifier]) {
        NSCustomTouchBarItem* item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[_installButton, _laterButton, _skipButton]];
        return item;
    }
    return nil;
}

@end

#endif
