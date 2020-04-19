//
//  Copyright 2006 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <os/trace.h>
#import <os/activity.h>

#import "SRCommon.h"
#import "SRKeyCodeTransformer.h"
#import "SRShortcut.h"

#import "SRShortcutValidator.h"


@implementation SRShortcutValidator

- (instancetype)initWithDelegate:(NSObject<SRShortcutValidatorDelegate> *)aDelegate
{
    self = [super init];

    if (self)
    {
        _delegate = aDelegate;
    }

    return self;
}

- (instancetype)init
{
    return [self initWithDelegate:nil];
}


#pragma mark Methods

- (BOOL)validateShortcut:(SRShortcut *)aShortcut error:(NSError * __autoreleasing *)outError
{
    __block BOOL result = NO;
    os_activity_initiate("-[SRShortcutValidator validateShortcut:error:]", OS_ACTIVITY_FLAG_DEFAULT, ^{
        __auto_type strongDelegate = self.delegate;

        if (![self validateShortcutAgainstDelegate:aShortcut error:outError])
        {
            result = NO;
        }
        else if ((![strongDelegate respondsToSelector:@selector(shortcutValidatorShouldCheckSystemShortcuts:)] ||
                  [strongDelegate shortcutValidatorShouldCheckSystemShortcuts:self]) &&
                 ![self validateShortcutAgainstSystemShortcuts:aShortcut error:outError])
        {
            result = NO;
        }
        else if ((![strongDelegate respondsToSelector:@selector(shortcutValidatorShouldCheckMenu:)] ||
                  [strongDelegate shortcutValidatorShouldCheckMenu:self]) &&
                 NSApp.mainMenu &&
                 ![self validateShortcut:aShortcut againstMenu:NSApp.mainMenu error:outError])
        {
            result = NO;
        }
        else
        {
            result = YES;
        }
    });

    return result;
}

- (BOOL)validateShortcutAgainstDelegate:(SRShortcut *)aShortcut error:(NSError * __autoreleasing *)outError
{
    if (!self.delegate)
        return YES;

    __block BOOL result = YES;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    __auto_type DelegateIsShortcutValid = ^(NSString * __autoreleasing * aReason) {
        __auto_type strongDelegate = self.delegate;

        if ([strongDelegate respondsToSelector:@selector(shortcutValidator:isShortcutValid:reason:)])
        {
            return [strongDelegate shortcutValidator:self
                                     isShortcutValid:aShortcut
                                              reason:aReason];
        }
        else if ([strongDelegate respondsToSelector:@selector(shortcutValidator:isKeyCode:andFlagsTaken:reason:)])
        {
            return (BOOL)![strongDelegate shortcutValidator:self
                                                  isKeyCode:aShortcut.keyCode
                                              andFlagsTaken:aShortcut.modifierFlags
                                                     reason:aReason];
        }
        else
            return YES;
    };
#pragma clang diagnostic pop

    os_activity_initiate("-[SRShortcutValidator validateShortcutAgainstDelegate:error:]", OS_ACTIVITY_FLAG_DEFAULT, (^{
        NSString *delegateReason = nil;
        if (!DelegateIsShortcutValid(&delegateReason))
        {
            if (outError)
            {
                BOOL isASCIIOnly = YES;
                __auto_type strongDelegate = self.delegate;

                if ([strongDelegate respondsToSelector:@selector(shortcutValidatorShouldUseASCIIStringForKeyCodes:)])
                    isASCIIOnly = [strongDelegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];

                NSString *shortcut = [aShortcut readableStringRepresentation:isASCIIOnly];
                NSString *failureReason = [NSString stringWithFormat:SRLoc(@"The \"%@\" shortcut can't be used!"), shortcut];
                NSString *description = nil;

                if (delegateReason.length)
                    description = [NSString stringWithFormat:SRLoc(@"The \"%@\" shortcut can't be used because %@."), shortcut, delegateReason];
                else
                    description = [NSString stringWithFormat:SRLoc(@"The \"%@\" shortcut is already in use."), shortcut];

                NSDictionary *userInfo = @{
                    NSLocalizedFailureReasonErrorKey : failureReason,
                    NSLocalizedDescriptionKey: description
               };

                *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
            }

            result = NO;
        }
    }));

    return result;
}

- (BOOL)validateShortcutAgainstSystemShortcuts:(SRShortcut *)aShortcut error:(NSError * __autoreleasing *)outError
{
    __block BOOL result = NO;
    os_activity_initiate("-[SRShortcutValidator validateShortcutAgainstSystemShortcuts:error:]", OS_ACTIVITY_FLAG_DEFAULT, (^{
        CFArrayRef s = NULL;
        OSStatus err = CopySymbolicHotKeys(&s);

        if (err != noErr)
        {
            os_trace_error("#Error Unable to read System Shortcuts: %d", err);
            result = NO;
            return;
        }

        NSArray *symbolicHotKeys = (NSArray *)CFBridgingRelease(s);

        for (NSDictionary *symbolicHotKey in symbolicHotKeys)
        {
            if ((__bridge CFBooleanRef)symbolicHotKey[(__bridge NSString *)kHISymbolicHotKeyEnabled] != kCFBooleanTrue)
                continue;

            NSUInteger symbolicHotKeyCode = [symbolicHotKey[(__bridge NSString *)kHISymbolicHotKeyCode] unsignedIntegerValue];

            if (symbolicHotKeyCode == aShortcut.keyCode)
            {
                UInt32 symbolicHotKeyFlags = [symbolicHotKey[(__bridge NSString *)kHISymbolicHotKeyModifiers] unsignedIntValue];
                symbolicHotKeyFlags &= SRCarbonModifierFlagsMask;

                if (SRCarbonToCocoaFlags(symbolicHotKeyFlags) == aShortcut.modifierFlags)
                {
                    if (outError)
                    {
                        BOOL isASCIIOnly = YES;
                        __auto_type strongDelegate = self.delegate;

                        if ([strongDelegate respondsToSelector:@selector(shortcutValidatorShouldUseASCIIStringForKeyCodes:)])
                            isASCIIOnly = [strongDelegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];

                        NSString *shortcut = [aShortcut readableStringRepresentation:isASCIIOnly];
                        NSString *failureReason = [NSString stringWithFormat:
                                                   SRLoc(@"The \"%@\" shortcut can't be used!"),
                                                   shortcut];
                        NSString *description = [NSString stringWithFormat:
                                                 SRLoc(@"The \"%@\" shortcut can't be used because it's already used by a system-wide keyboard shortcut. If you really want to use this shortcut, most shortcuts can be changed in the Keyboard panel in System Preferences."),
                                                 shortcut];
                        NSDictionary *userInfo = @{
                            NSLocalizedFailureReasonErrorKey: failureReason,
                            NSLocalizedDescriptionKey: description
                        };
                        *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
                    }

                    result = NO;
                    return;
                }
            }
        }

        result = YES;
    }));

    return result;
}

- (BOOL)validateShortcut:(SRShortcut *)aShortcut againstMenu:(NSMenu *)aMenu error:(NSError * __autoreleasing *)outError
{
    __block BOOL result = NO;

    os_activity_initiate("-[SRShortcutValidator validateShortcut:againstMenu:error:]", OS_ACTIVITY_FLAG_DEFAULT, (^{
        for (NSMenuItem *menuItem in aMenu.itemArray)
        {
            if (menuItem.hasSubmenu && ![self validateShortcut:aShortcut againstMenu:menuItem.submenu error:outError])
            {
                result = NO;
                return;
            }

            NSString *keyEquivalent = menuItem.keyEquivalent;

            if (!keyEquivalent.length)
                continue;

            NSEventModifierFlags keyEquivalentModifierMask = menuItem.keyEquivalentModifierMask;

            if ([aShortcut isEqualToKeyEquivalent:keyEquivalent withModifierFlags:keyEquivalentModifierMask])
            {
                if (outError)
                {
                    BOOL isASCIIOnly = YES;
                    __auto_type strongDelegate = self.delegate;

                    if ([strongDelegate respondsToSelector:@selector(shortcutValidatorShouldUseASCIIStringForKeyCodes:)])
                        isASCIIOnly = [strongDelegate shortcutValidatorShouldUseASCIIStringForKeyCodes:self];

                    NSString *shortcut = [aShortcut readableStringRepresentation:isASCIIOnly];
                    NSString *failureReason = [NSString stringWithFormat:SRLoc(@"The \"%@\" shortcut can't be used!"), shortcut];
                    NSString *description = [NSString stringWithFormat:SRLoc(@"The \"%@\" shortcut can't be used because it's already used by the \"%@\" menu item."), shortcut, menuItem.SR_path];
                    NSDictionary *userInfo = @{
                        NSLocalizedFailureReasonErrorKey: failureReason,
                        NSLocalizedDescriptionKey: description
                    };
                    *outError = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:userInfo];
                }

                result = NO;
                return;
            }
        }

        result = YES;
    }));

    return result;
}


#pragma mark SRRecorderControlDelegate

- (BOOL)recorderControl:(SRRecorderControl *)aRecorder canRecordShortcut:(SRShortcut *)aShortcut
{
    NSError *error = nil;
    BOOL isValid = [self validateShortcut:aShortcut error:&error];

    if (!isValid)
    {
        if (aRecorder.window)
        {
            [aRecorder presentError:error
                     modalForWindow:aRecorder.window
                           delegate:nil
                 didPresentSelector:NULL
                        contextInfo:NULL];
        }
        else
            [aRecorder presentError:error];
    }

    return isValid;
}


#pragma mark Deprecated

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlagsTaken:(NSEventModifierFlags)aFlags error:(NSError * __autoreleasing *)outError;
{
    return ![self validateShortcut:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] error:outError];
}

- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlagTakenInDelegate:(NSEventModifierFlags)aFlags error:(NSError * __autoreleasing *)outError
{
    return ![self validateShortcutAgainstDelegate:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] error:outError];
}

- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlagsTakenInSystemShortcuts:(NSEventModifierFlags)aFlags error:(NSError * __autoreleasing *)outError
{
    return ![self validateShortcutAgainstSystemShortcuts:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] error:outError];
}

- (BOOL)isKeyCode:(SRKeyCode)aKeyCode andFlags:(NSEventModifierFlags)aFlags takenInMenu:(NSMenu *)aMenu error:(NSError * __autoreleasing *)outError
{
    return ![self validateShortcut:[SRShortcut shortcutWithCode:aKeyCode modifierFlags:aFlags characters:nil charactersIgnoringModifiers:nil] againstMenu:aMenu error:outError];
}

#pragma clang diagnostic pop

@end


@implementation NSMenuItem (SRShortcutValidator)

- (NSString *)SR_path
{
    NSMutableArray *items = [NSMutableArray array];
    static const NSUInteger Limit = 1000;
    static const NSString *Delimeter = @" → ";
    NSMenuItem *currentMenuItem = self;
    NSUInteger i = 0;

    do
    {
        [items insertObject:currentMenuItem atIndex:0];
        currentMenuItem = currentMenuItem.parentItem;
        ++i;
    }
    while (currentMenuItem && i < Limit);

    NSMutableString *path = [NSMutableString string];

    for (NSMenuItem *menuItem in items)
        [path appendFormat:@"%@%@", menuItem.title, Delimeter];

    if (path.length > Delimeter.length)
        [path deleteCharactersInRange:NSMakeRange(path.length - Delimeter.length, Delimeter.length)];

    return path;
}

@end
