//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUUpdatePermissionPrompt.h"
#import "SPUUpdatePermissionRequest.h"
#import "SUUpdatePermissionResponse.h"
#import "SULocalizations.h"

#import "SUHost.h"
#import "SUConstants.h"
#import "SUApplicationInfo.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUUpdatePermissionPromptTouchBarIdentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdatePermissionPrompt";

@interface SUUpdatePermissionPrompt () <NSTouchBarDelegate>

// These properties are used for bindings
@property (nonatomic, readonly) NSArray *systemProfileInformationArray;
@property (nonatomic) BOOL shouldSendProfile;
@property (nonatomic) BOOL automaticallyDownloadUpdates;

@end

@implementation SUUpdatePermissionPrompt
{
    SUHost *_host;
    
    IBOutlet NSStackView *_stackView;
    IBOutlet NSView *_promptView;
    IBOutlet NSView *_moreInfoView;
    IBOutlet NSView *_placeholderView;
    IBOutlet NSView *_responseView;
    IBOutlet NSView *_infoChoiceView;
    IBOutlet NSView *_automaticallyDownloadUpdatesView;
    IBOutlet NSButton *_cancelButton;
    IBOutlet NSButton *_checkButton;
    IBOutlet NSTextField *_checkForUpdatesAutomaticallyTextField;
    IBOutlet NSButton *_includeAnonymousSystemProfileButton;
    IBOutlet NSButton *_anonymousInfoDisclosureButton;
    IBOutlet NSButton *_automaticallyDownloadAndInstallUpdatesButton;
    IBOutlet NSTextField *_anonymousSystemProfileDisclosureInformation;
    IBOutlet NSLayoutConstraint *_placeholderHeightLayoutConstraint;
    
    void (^_reply)(SUUpdatePermissionResponse *);
}

@synthesize shouldSendProfile = _shouldSendProfile;
@synthesize automaticallyDownloadUpdates = _automaticallyDownloadUpdates;
@synthesize systemProfileInformationArray = _systemProfileInformationArray;

- (instancetype)initPromptWithHost:(SUHost *)theHost request:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    self = [super initWithWindowNibName:@"SUUpdatePermissionPrompt"];
    if (self)
    {
        _reply = [reply copy];
        _host = theHost;
        _shouldSendProfile = [self shouldAskAboutProfile];
        _systemProfileInformationArray = request.systemProfile;
        _automaticallyDownloadUpdates = [theHost boolForKey:SUAutomaticallyUpdateKey];
        [self setShouldCascadeWindows:NO];
    } else {
        assert(false);
    }
    return self;
}

- (BOOL)shouldAskAboutProfile
{
    return [_host boolForInfoDictionaryKey:SUEnableSystemProfilingKey];
}

- (BOOL)allowsAutomaticUpdates
{
    NSNumber *allowsAutomaticUpdates = [_host boolNumberForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
    return (allowsAutomaticUpdates == nil || allowsAutomaticUpdates.boolValue);
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath]; }

- (void)windowDidLoad
{
    [self.window center];
    
    _infoChoiceView.hidden = ![self shouldAskAboutProfile];
    _automaticallyDownloadUpdatesView.hidden = ![self allowsAutomaticUpdates];
    
    [_stackView addArrangedSubview:_promptView];
    [_stackView addArrangedSubview:_automaticallyDownloadUpdatesView];
    [_stackView addArrangedSubview:_infoChoiceView];
    [_stackView addArrangedSubview:_placeholderView];
    [_stackView addArrangedSubview:_moreInfoView];
    [_stackView addArrangedSubview:_responseView];
    
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    _checkButton.title = SULocalizedStringFromTableInBundle(@"Check Automatically", SPARKLE_TABLE, sparkleBundle, nil);
    _cancelButton.title = SULocalizedStringFromTableInBundle(@"Don’t Check", SPARKLE_TABLE, sparkleBundle, nil);
    _checkForUpdatesAutomaticallyTextField.stringValue = SULocalizedStringFromTableInBundle(@"Check for updates automatically?", SPARKLE_TABLE, sparkleBundle, nil);
    _includeAnonymousSystemProfileButton.title = SULocalizedStringFromTableInBundle(@"Include anonymous system profile", SPARKLE_TABLE, sparkleBundle, nil);
    _automaticallyDownloadAndInstallUpdatesButton.title = SULocalizedStringFromTableInBundle(@"Automatically download and install updates", SPARKLE_TABLE, sparkleBundle, nil);
    _anonymousSystemProfileDisclosureInformation.stringValue = SULocalizedStringFromTableInBundle(@"Anonymous system profile information is used to help us plan future development work. Please contact us if you have any questions about this.\n\nThis is the information that would be sent:", SPARKLE_TABLE, sparkleBundle, nil);
}

- (BOOL)tableView:(NSTableView *) __unused tableView shouldSelectRow:(NSInteger) __unused row { return NO; }


- (NSImage *)icon
{
    return [SUApplicationInfo bestIconForHost:_host];
}

- (NSString *)promptDescription
{
    return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", SPARKLE_TABLE, SUSparkleBundle(), nil), _host.name];
}

- (IBAction)toggleMoreInfo:(id)__unused sender
{
    // Use a placeholder view to unhide/hide before putting the more info view in place
    // This allows us to animate resizing the more info view in place more easily
    
    static const CGFloat TOGGLE_INFO_ANIMATION_DURATION = 0.2;
    
    BOOL disclosingInfo = (_anonymousInfoDisclosureButton.state == NSControlStateValueOn);
    
    if (disclosingInfo) {
        _placeholderHeightLayoutConstraint.constant = 0.0;
        _placeholderView.hidden = NO;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = TOGGLE_INFO_ANIMATION_DURATION;
            
            self->_placeholderHeightLayoutConstraint.animator.constant = _moreInfoView.frame.size.height;
        } completionHandler:^{
            self->_placeholderView.hidden = YES;
            self->_moreInfoView.hidden = NO;
        }];
    } else {
        _placeholderHeightLayoutConstraint.constant = _moreInfoView.frame.size.height;
        _moreInfoView.hidden = YES;
        _placeholderView.hidden = NO;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = TOGGLE_INFO_ANIMATION_DURATION;
            
            self->_placeholderHeightLayoutConstraint.animator.constant = 0.0;
        } completionHandler:^{
            self->_placeholderView.hidden = YES;
        }];
    }
}

- (IBAction)finishPrompt:(NSButton *)sender
{
    BOOL automaticUpdateChecksEnabled = ([sender tag] == 1);
    
    NSNumber *automaticUpdateDownloading;
    if ([self allowsAutomaticUpdates]) {
        automaticUpdateDownloading = @(automaticUpdateChecksEnabled && _automaticallyDownloadUpdates);
    } else {
        automaticUpdateDownloading = nil;
    }
    
    SUUpdatePermissionResponse *response = [[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:automaticUpdateChecksEnabled automaticUpdateDownloading:automaticUpdateDownloading sendSystemProfile:_shouldSendProfile];
    _reply(response);
    
    [self close];
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdatePermissionPromptTouchBarIdentifier,];
    touchBar.principalItemIdentifier = SUUpdatePermissionPromptTouchBarIdentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUUpdatePermissionPromptTouchBarIdentifier]) {
        NSCustomTouchBarItem* item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[_checkButton, _cancelButton]];
        return item;
    }
    return nil;
}

@end

#endif
