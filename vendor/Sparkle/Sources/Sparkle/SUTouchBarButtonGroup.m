//
//  SUTouchBarButtonGroup.m
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import "SUTouchBarButtonGroup.h"

@implementation SUTouchBarButtonGroup

@synthesize buttons = _buttons;

- (instancetype)initByReferencingButtons:(NSArray<NSButton *> *)buttons
{
    if (!(self = [super init]))
        return self;

    NSView *buttonGroup = [[NSView alloc] initWithFrame:NSZeroRect];
    self.view = buttonGroup;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    NSMutableArray<NSButton *> *buttonCopies = [NSMutableArray arrayWithCapacity:buttons.count];

    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton *button = [buttons objectAtIndex:i];
        NSButton *buttonCopy = [NSButton buttonWithTitle:button.title target:button.target action:button.action];
        buttonCopy.tag = button.tag;
        buttonCopy.enabled = button.enabled;

        // Must be set explicitly, because NSWindow clears it
        // https://github.com/sparkle-project/Sparkle/pull/987#issuecomment-271539319
        if (i == 0) {
            buttonCopy.keyEquivalent = @"\r";
        }

        buttonCopy.translatesAutoresizingMaskIntoConstraints = NO;

        [buttonCopies addObject:buttonCopy];
        [buttonGroup addSubview:buttonCopy];

        // Custom layout is used for equal width buttons, to look more keyboard-like and mimic standard alerts
        // https://github.com/sparkle-project/Sparkle/pull/987#issuecomment-272324726
        [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0]];
        [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]];
        if (i == 0) {
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0]];
        } else {
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:[buttonCopies objectAtIndex:i - 1] attribute:NSLayoutAttributeLeading multiplier:1.0 constant:(i == 1) ? -8 : -32]];
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:[buttonCopies objectAtIndex:i - 1] attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0.0]];
            constraints.lastObject.priority = 250;
        }
        if (i == buttons.count - 1) {
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0]];
        }
    }
    [NSLayoutConstraint activateConstraints:constraints];

    _buttons = buttonCopies;
    return self;
}

@end

#endif
