//
//  Copyright 2018 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Carbon/Carbon.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/objc-runtime.h>

#import "SRKeyCodeTransformer.h"
#import "SRKeyEquivalentTransformer.h"
#import "SRKeyEquivalentModifierMaskTransformer.h"
#import "SRModifierFlagsTransformer.h"

#import "SRShortcutController.h"


SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyKeyEquivalent = @"keyEquivalent";
SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyKeyEquivalentModifierMask = @"keyEquivalentModifierMask";

SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyLiteralKeyCode = @"literalKeyCode";
SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeySymbolicKeyCode = @"symbolicKeyCode";

SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyLiteralASCIIKeyCode = @"literalASCIIKeyCode";
SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeySymbolicASCIIKeyCode = @"symbolicASCIIKeyCode";

SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyLiteralModifierFlags = @"literalModifierFlags";
SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeySymbolicModifierFlags = @"symbolicModifierFlags";


SRShortcutControllerKeyPath const SRShortcutControllerKeyPathKeyEquivalent = @"selection.keyEquivalent";
SRShortcutControllerKeyPath const SRShortcutControllerKeyPathKeyEquivalentModifierMask = @"selection.keyEquivalentModifierMask";

SRShortcutControllerKeyPath const SRShortcutControllerKeyPathLiteralKeyCode = @"selection.literalKeyCode";
SRShortcutControllerKeyPath const SRShortcutControllerKeyPathSymbolicKeyCode = @"selection.symbolicKeyCode";

SRShortcutControllerKeyPath const SRShortcutControllerKeyPathLiteralASCIIKeyCode = @"selection.literalASCIIKeyCode";
SRShortcutControllerKeyPath const SRShortcutControllerKeyPathSymbolicASCIIKeyCode = @"selection.symbolicASCIIKeyCode";

SRShortcutControllerKeyPath const SRShortcutControllerKeyPathLiteralModifierFlags = @"selection.literalModifierFlags";
SRShortcutControllerKeyPath const SRShortcutControllerKeyPathSymbolicModifierFlags = @"selection.symbolicModifierFlags";


static void _onSelectedKeyboardInputSourceChange(CFNotificationCenterRef aCenter,
                                                 void *anObserver,
                                                 CFNotificationName aName,
                                                 const void *anObject,
                                                 CFDictionaryRef aUserInfo)
{
    [(__bridge SRShortcutController *)anObserver onSelectedKeyboardInputSourceObserverChange];
}


@implementation SRShortcutController
{
    NSString *_keyEquivalent;
    NSNumber *_keyEquivalentModifierMask;
    NSString *_literalKeyCode;
    NSString *_symbolicKeyCode;
    NSString *_literalASCIIKeyCode;
    NSString *_symbolicASCIIKeyCode;
    NSString *_literalModifierFlags;
    NSString *_symbolicModifierFlags;

    BOOL _isSelectedKeyboardInputSourceObserved;

    __weak SRRecorderControl *_recorderControl;
}

- (instancetype)initWithContent:(SRShortcut *)aContent
{
    self = [super initWithContent:aContent];
    [self initInternalState];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aCoder
{
    self = [super initWithCoder:aCoder];
    [self initInternalState];
    return self;
}

- (void)initInternalState
{
    if (self.content == nil)
    {
        _keyEquivalent = (id)NSNoSelectionMarker;
        _keyEquivalentModifierMask = (id)NSNoSelectionMarker;
        _literalKeyCode = (id)NSNoSelectionMarker;
        _symbolicKeyCode = (id)NSNoSelectionMarker;
        _literalASCIIKeyCode = (id)NSNoSelectionMarker;
        _symbolicASCIIKeyCode = (id)NSNoSelectionMarker;
        _literalModifierFlags = (id)NSNoSelectionMarker;
        _symbolicModifierFlags = (id)NSNoSelectionMarker;
    }
}

- (void)dealloc
{
    [self removeSelectedKeyboardInputSourceObserverIfNeeded];
}


#pragma mark Properties
+ (BOOL)automaticallyNotifiesObserversOfShortcutActionTarget
{
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversOfShortcutAction
{
    return NO;
}

- (id)shortcutActionTarget
{
    return _shortcutAction.target;
}

- (void)setShortcutActionTarget:(id)newShortcutActionTarget
{
    if (_shortcutAction.target == newShortcutActionTarget)
        return;

    [self willChangeValueForKey:@"shortcutActionTarget"];

    if (!newShortcutActionTarget && _shortcutAction)
    {
        [self willChangeValueForKey:@"shortcutAction"];
        [SRGlobalShortcutMonitor.sharedMonitor removeAction:_shortcutAction];
        _shortcutAction = nil;
        [self didChangeValueForKey:@"shortcutAction"];
    }
    else if (newShortcutActionTarget && !_shortcutAction)
    {
        [self willChangeValueForKey:@"shortcutAction"];
        SRShortcutAction *action = [SRShortcutAction shortcutActionWithKeyPath:@"content"
                                                                      ofObject:self
                                                                        target:newShortcutActionTarget
                                                                        action:nil
                                                                           tag:0];
        action.identifier = self.identifier;
        _shortcutAction = action;
        [SRGlobalShortcutMonitor.sharedMonitor addAction:_shortcutAction forKeyEvent:SRKeyEventTypeDown];
        [self didChangeValueForKey:@"shortcutAction"];
    }
    else
        _shortcutAction.target = newShortcutActionTarget;

    [self didChangeValueForKey:@"shortcutActionTarget"];
}

- (SRRecorderControl *)recorderControl
{
    return _recorderControl;
}

- (void)setRecorderControl:(SRRecorderControl *)newRecorderControl
{
    [_recorderControl unbind:NSValueBinding];
    _recorderControl = newRecorderControl;
    [self _updateRecorderControlValueBinding];
}


#pragma mark SelectedKeyboardInputSourceObserver

- (void)addSelectedKeyboardInputSourceObserverIfNeeded
{
    if (_isSelectedKeyboardInputSourceObserved)
        return;

    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(),
                                    (__bridge const void *)(self),
                                    _onSelectedKeyboardInputSourceChange,
                                    kTISNotifySelectedKeyboardInputSourceChanged,
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
    _isSelectedKeyboardInputSourceObserved = YES;
}

- (void)removeSelectedKeyboardInputSourceObserverIfNeeded
{
    if (!_isSelectedKeyboardInputSourceObserved)
        return;

    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDistributedCenter(),
                                       (__bridge const void *)(self),
                                       kTISNotifySelectedKeyboardInputSourceChanged,
                                       NULL);
    _isSelectedKeyboardInputSourceObserved = NO;
}

- (void)onSelectedKeyboardInputSourceObserverChange
{
    // It might seem that willChange / didChange should have been called for the selection instead.
    // However the selection does not implement KVO directly meaning that a user of NSObjectController
    // should subscribe to particular keys of the content via @"selection.<key>" for all keys.
    [self willChangeValueForKey:SRShortcutControllerKeyPathKeyEquivalent];
    [self willChangeValueForKey:SRShortcutControllerKeyPathLiteralKeyCode];
    [self willChangeValueForKey:SRShortcutControllerKeyPathSymbolicKeyCode];
    [self willChangeValueForKey:SRShortcutControllerKeyPathLiteralASCIIKeyCode];
    [self willChangeValueForKey:SRShortcutControllerKeyPathSymbolicASCIIKeyCode];
    [self updateComputedKeyPaths];
    [self didChangeValueForKey:SRShortcutControllerKeyPathSymbolicASCIIKeyCode];
    [self didChangeValueForKey:SRShortcutControllerKeyPathLiteralASCIIKeyCode];
    [self didChangeValueForKey:SRShortcutControllerKeyPathSymbolicKeyCode];
    [self didChangeValueForKey:SRShortcutControllerKeyPathLiteralKeyCode];
    [self willChangeValueForKey:SRShortcutControllerKeyPathKeyEquivalent];
}

- (void)updateComputedKeyPaths
{
    NSNumber *keyCode = [self valueForKeyPath:@"selection.keyCode"];

    if (NSIsControllerMarker(keyCode))
    {
        _keyEquivalent = (id)keyCode;
        _keyEquivalentModifierMask = (id)keyCode;
        _literalKeyCode = (id)keyCode;
        _symbolicKeyCode = (id)keyCode;
        _literalASCIIKeyCode = (id)keyCode;
        _symbolicASCIIKeyCode = (id)keyCode;
        _literalModifierFlags = (id)keyCode;
        _symbolicModifierFlags = (id)keyCode;
    }
    else
    {
        NSNumber *modifierFlags = [self valueForKeyPath:@"selection.modifierFlags"];
        SRShortcut *selection = [SRShortcut shortcutWithCode:keyCode.unsignedShortValue
                                               modifierFlags:modifierFlags.unsignedIntegerValue
                                                  characters:nil
                                 charactersIgnoringModifiers:nil];
        _keyEquivalent = [SRKeyEquivalentTransformer.sharedTransformer transformedValue:selection];
        _keyEquivalentModifierMask = [SRKeyEquivalentModifierMaskTransformer.sharedTransformer transformedValue:selection];
        _literalKeyCode = [SRLiteralKeyCodeTransformer.sharedTransformer transformedValue:keyCode];
        _symbolicKeyCode = [SRSymbolicKeyCodeTransformer.sharedTransformer transformedValue:keyCode];
        _literalASCIIKeyCode = [SRASCIILiteralKeyCodeTransformer.sharedTransformer transformedValue:keyCode];
        _symbolicASCIIKeyCode = [SRASCIISymbolicKeyCodeTransformer.sharedTransformer transformedValue:keyCode];
        _literalModifierFlags = [SRLiteralModifierFlagsTransformer.sharedTransformer transformedValue:modifierFlags];
        _symbolicModifierFlags = [SRSymbolicModifierFlagsTransformer.sharedTransformer transformedValue:modifierFlags];
    }
}

- (void)_updateRecorderControlValueBinding
{
    __auto_type strongRecorderControl = _recorderControl;

    if (!strongRecorderControl)
        return;

    NSDictionary *contentBindingInfo = [self infoForBinding:NSContentObjectBinding];
    if (!contentBindingInfo)
        return;

    NSDictionary *bindingOptions = [contentBindingInfo[NSOptionsKey] dictionaryWithValuesForKeys:@[NSValueTransformerBindingOption, NSValueTransformerNameBindingOption]];
    [strongRecorderControl bind:NSValueBinding
                       toObject:contentBindingInfo[NSObservedObjectKey]
                    withKeyPath:contentBindingInfo[NSObservedKeyPathKey]
                        options:bindingOptions];
}


#pragma mark NSKeyValueCoding

- (id)valueForKeyPath:(NSString *)aKeyPath
{
    if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathKeyEquivalent])
        return _keyEquivalent;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathKeyEquivalentModifierMask])
        return _keyEquivalentModifierMask;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathLiteralKeyCode])
        return _literalKeyCode;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathSymbolicKeyCode])
        return _symbolicKeyCode;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathLiteralASCIIKeyCode])
        return _literalASCIIKeyCode;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathSymbolicASCIIKeyCode])
        return _symbolicASCIIKeyCode;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathLiteralModifierFlags])
        return _literalModifierFlags;
    else if ([aKeyPath isEqualToString:SRShortcutControllerKeyPathSymbolicModifierFlags])
        return _symbolicModifierFlags;
    else
        return [super valueForKeyPath:aKeyPath];
}


#pragma mark NSKeyValueBindingCreation

- (void)bind:(NSBindingName)aBinding toObject:(id)anObservable withKeyPath:(NSString *)aKeyPath options:(NSDictionary<NSBindingOption, id> *)anOptions
{
    [super bind:aBinding toObject:anObservable withKeyPath:aKeyPath options:anOptions];

    if ([aBinding isEqualToString:NSContentObjectBinding])
        [self _updateRecorderControlValueBinding];
}


#pragma mark NSKeyValueObserving

- (void)didChangeValueForKey:(NSString *)aKey
{
    if ([aKey isEqualToString:@"selection"])
    {
        if (self.content != nil)
            [self addSelectedKeyboardInputSourceObserverIfNeeded];
        else
            [self removeSelectedKeyboardInputSourceObserverIfNeeded];

        [self updateComputedKeyPaths];
    }

    [super didChangeValueForKey:aKey];
}


#pragma mark NSUserInterfaceItemIdentifier
@synthesize identifier = _identifier;

- (NSString *)identifier
{
    return _identifier;
}

- (void)setIdentifier:(NSString *)newIdentifier
{
    _identifier = [newIdentifier copy];
    _shortcutAction.identifier = newIdentifier;
}


#pragma mark NSObjectController
@dynamic content;

- (Class)objectClass
{
    return SRShortcut.class;
}

- (id)newObject
{
    [NSException raise:NSInternalInconsistencyException format:@"newObject is not implemented"];
    __builtin_unreachable();
    return nil;
}

- (void)addObject:(SRShortcut *)anObject
{
    return [self addObject:anObject];
}

- (void)removeObject:(SRShortcut *)anObject
{
    return [self removeObject:anObject];
}

- (id)_singleValueForKey:(NSString *)aKey
{
    // _NSControllerObjectProxy forwards KVC access to its controller.
    if ([aKey isEqualToString:SRShortcutControllerSelectionKeyKeyEquivalent])
        return _keyEquivalent;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeyKeyEquivalentModifierMask])
        return _keyEquivalentModifierMask;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeyLiteralKeyCode])
        return _literalKeyCode;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeySymbolicKeyCode])
        return _symbolicKeyCode;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeyLiteralASCIIKeyCode])
        return _literalASCIIKeyCode;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeySymbolicASCIIKeyCode])
        return _symbolicASCIIKeyCode;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeyLiteralModifierFlags])
        return _literalModifierFlags;
    else if ([aKey isEqualToString:SRShortcutControllerSelectionKeySymbolicModifierFlags])
        return _symbolicModifierFlags;
    else
    {
        struct objc_super superInfo = {
            .receiver = self,
            .super_class = [self superclass]
        };
        __auto_type superSingleValueForKey = (id (*)(struct objc_super*, SEL, NSString *))objc_msgSendSuper;
        return superSingleValueForKey(&superInfo, @selector(_singleValueForKey:), aKey);
    }
}

@end
