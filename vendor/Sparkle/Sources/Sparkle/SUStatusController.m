//
//  SUStatusController.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/14/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import "SUStatusController.h"
#import "SUHost.h"
#import "SUApplicationInfo.h"
#import "SULocalizations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUStatusControllerTouchBarIdentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUStatusController";

@interface SUStatusController () <NSTouchBarDelegate>

// These properties are used for bindings
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *buttonTitle;

@end

@implementation SUStatusController
{
    NSString *_windowTitle;
    NSValue *_centerPointValue;
    NSString *_title;
    NSString *_buttonTitle;
    SUHost *_host;
    NSButton *_touchBarButton;
    
    IBOutlet NSButton *_actionButton;
    IBOutlet NSTextField *_statusTextField;
    IBOutlet NSProgressIndicator *_progressBar;
    
    BOOL _minimizable;
    BOOL _closable;
}

@synthesize title = _title;
@synthesize buttonTitle = _buttonTitle;
@synthesize progressValue = _progressValue;
@synthesize maxProgressValue = _maxProgressValue;
@synthesize statusText = _statusText;

- (instancetype)initWithHost:(SUHost *)aHost windowTitle:(NSString *)windowTitle centerPointValue:(NSValue *)centerPointValue minimizable:(BOOL)minimizable closable:(BOOL)closable
{
    self = [super initWithWindowNibName:@"SUStatus" owner:self];
	if (self)
	{
        _host = aHost;
        _centerPointValue = centerPointValue;
        _minimizable = minimizable;
        _closable = closable;
        _windowTitle = [windowTitle copy];
        [self setShouldCascadeWindows:NO];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath];
}

- (void)windowDidLoad 
{
    NSWindow *window = self.window;
    NSRect windowFrame = window.frame;
    
    if (_centerPointValue != nil) {
        NSPoint centerPoint = _centerPointValue.pointValue;
        [window setFrameOrigin:NSMakePoint(centerPoint.x - windowFrame.size.width / 2.0, centerPoint.y - windowFrame.size.height / 2.0)];
    } else {
        [window center];
    }
    
    if (_minimizable) {
        window.styleMask = (NSWindowStyleMask)(window.styleMask | NSWindowStyleMaskMiniaturizable);
    }
    if (_closable) {
        window.styleMask = (NSWindowStyleMask)(window.styleMask | NSWindowStyleMaskClosable);
    }
    [_progressBar setUsesThreadedAnimation:YES];
    [_statusTextField setFont:[NSFont monospacedDigitSystemFontOfSize:0 weight:NSFontWeightRegular]];
    
    if (@available(macOS 16, *)) {
        _actionButton.controlSize = NSControlSizeLarge;
    }
    
    window.title = _windowTitle;
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:_host];
}

- (void)beginActionWithTitle:(NSString *)aTitle maxProgressValue:(double)aMaxProgressValue statusText:(NSString *)aStatusText
{
    self.title = aTitle;

    self.maxProgressValue = aMaxProgressValue;
    self.statusText = aStatusText;
}

- (void)setButtonTitle:(NSString *)aButtonTitle target:(id)target action:(SEL)action isDefault:(BOOL)isDefault accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    self.buttonTitle = aButtonTitle;
    _actionButton.accessibilityIdentifier = [accessibilityIdentifier copy];

    [self window];
    [_actionButton sizeToFit];
    // Except we're going to add 15 px for padding.
    [_actionButton setFrameSize:NSMakeSize(_actionButton.frame.size.width + 15, _actionButton.frame.size.height)];
    // Now we have to move it over so that it's always 15px from the side of the window.
    [_actionButton setFrameOrigin:NSMakePoint([[self window] frame].size.width - 15 - _actionButton.frame.size.width, _actionButton.frame.origin.y)];
    // Redisplay superview to clean up artifacts
    [[_actionButton superview] display];

    [_actionButton setTarget:target];
    [_actionButton setAction:action];
    [_actionButton setKeyEquivalent:isDefault ? @"\r" : @""];
    
    // False warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-repeated-use-of-weak"
    _touchBarButton.target = _actionButton.target;
#pragma clang diagnostic pop
    _touchBarButton.action = _actionButton.action;
    _touchBarButton.keyEquivalent = _actionButton.keyEquivalent;

    // 06/05/2008 Alex: Avoid a crash when cancelling during the extraction
    [self setButtonEnabled:(target != nil)];
}

- (BOOL)progressBarShouldAnimate
{
    return YES;
}

- (void)setButtonEnabled:(BOOL)enabled
{
    [_actionButton setEnabled:enabled];
}

- (BOOL)isButtonEnabled
{
    return [_actionButton isEnabled];
}

- (void)setMaxProgressValue:(double)value
{
	if (value < 0.0) value = 0.0;
    _maxProgressValue = value;
    [self setProgressValue:0.0];
    [_progressBar setIndeterminate:(value == 0.0)];
    [_progressBar startAnimation:self];
    [_progressBar setUsesThreadedAnimation:YES];
}


- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[ SUStatusControllerTouchBarIdentifier,];
    touchBar.principalItemIdentifier = SUStatusControllerTouchBarIdentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUStatusControllerTouchBarIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        SUTouchBarButtonGroup *group = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[_actionButton,]];
        item.viewController = group;
        _touchBarButton = group.buttons.firstObject;
        [_touchBarButton bind:@"title" toObject:_actionButton withKeyPath:@"title" options:nil];
        [_touchBarButton bind:@"enabled" toObject:_actionButton withKeyPath:@"enabled" options:nil];
        return item;
    }
    return nil;
}

@end

#endif
