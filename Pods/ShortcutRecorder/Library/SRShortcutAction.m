//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Carbon/Carbon.h>
#import <os/trace.h>
#import <os/activity.h>

#import "SRShortcutAction.h"
#import "SRCommon.h"


static void *_SRShortcutActionContext = &_SRShortcutActionContext;


@implementation SRShortcutAction
{
    SRShortcut *_shortcut;
    SRShortcutActionHandler _actionHandler;
    __weak id _target;
}

+ (instancetype)shortcutActionWithShortcut:(SRShortcut *)aShortcut
                                    target:(id)aTarget
                                    action:(SEL)anAction
                                       tag:(NSInteger)aTag
{
    SRShortcutAction *action = [self new];
    action.shortcut = aShortcut;
    action.target = aTarget;
    action.action = anAction;
    action.tag = aTag;
    return action;
}

+ (instancetype)shortcutActionWithShortcut:(SRShortcut *)aShortcut
                             actionHandler:(SRShortcutActionHandler)anActionHandler
{
    SRShortcutAction *action = [self new];
    action.shortcut = aShortcut;
    action.actionHandler = anActionHandler;
    return action;
}

+ (instancetype)shortcutActionWithKeyPath:(NSString *)aKeyPath
                                 ofObject:(id)anObject
                                   target:(id)aTarget
                                   action:(nullable SEL)anAction
                                      tag:(NSInteger)aTag
{
    SRShortcutAction *action = [self new];
    [action setObservedObject:anObject withKeyPath:aKeyPath];
    action.target = aTarget;
    action.action = anAction;
    action.tag = aTag;
    return action;
}

+ (instancetype)shortcutActionWithKeyPath:(NSString *)aKeyPath
                                 ofObject:(id)anObject
                            actionHandler:(SRShortcutActionHandler)anActionHandler
{
    SRShortcutAction *action = [self new];
    [action setObservedObject:anObject withKeyPath:aKeyPath];
    action.actionHandler = anActionHandler;
    return action;
}

- (instancetype)init
{
    self = [super init];

    if (self)
        _enabled = YES;

    return self;
}

- (void)dealloc
{
    [self _invalidateObserving];
}

#pragma mark Properties
@synthesize identifier;
@synthesize tag;

+ (BOOL)automaticallyNotifiesObserversOfShortcut
{
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversOfActionHandler
{
    return NO;
}

+ (BOOL)automaticallyNotifiesObserversOfTarget
{
    return NO;
}

- (SRShortcut *)shortcut
{
    @synchronized (self)
    {
        return _shortcut;
    }
}

- (void)setShortcut:(SRShortcut *)aShortcut
{
    os_activity_initiate("-[SRShortcutAction setShortcut:]", OS_ACTIVITY_FLAG_DEFAULT, ^{
        @synchronized (self)
        {
            [self willChangeValueForKey:@"observedObject"];
            [self willChangeValueForKey:@"observedKeyPath"];

            if (self->_shortcut != aShortcut && ![self->_shortcut isEqual:aShortcut])
            {
                [self willChangeValueForKey:@"shortcut"];
                [self _invalidateObserving];
                self->_shortcut = aShortcut;
                [self didChangeValueForKey:@"shortcut"];
            }
            else
                [self _invalidateObserving];

            [self didChangeValueForKey:@"observedKeyPath"];
            [self didChangeValueForKey:@"observedObject"];
        }
    });
}

- (void)setObservedObject:(id)newObservedObject withKeyPath:(NSString *)newKeyPath
{
    os_activity_initiate("-[SRShortcutAction setObservedObject:withKeyPath:]", OS_ACTIVITY_FLAG_DEFAULT, ^{
        @synchronized (self)
        {
            if (newObservedObject == self->_observedObject && [self->_observedKeyPath isEqualToString:newKeyPath])
                return;

            [self willChangeValueForKey:@"observedObject"];
            [self willChangeValueForKey:@"observedKeyPath"];

            [self _invalidateObserving];
            self->_observedObject = newObservedObject;
            self->_observedKeyPath = newKeyPath;
            [newObservedObject addObserver:self
                                forKeyPath:newKeyPath
                                   options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                                   context:_SRShortcutActionContext];

            [self didChangeValueForKey:@"observedKeyPath"];
            [self didChangeValueForKey:@"observedObject"];
        }
    });
}

- (SRShortcutActionHandler)actionHandler
{
    @synchronized (self)
    {
        return _actionHandler;
    }
}

- (void)setActionHandler:(SRShortcutActionHandler)newActionHandler
{
    @synchronized (self)
    {
        [self willChangeValueForKey:@"actionHandler"];
        _actionHandler = newActionHandler;

        if (_actionHandler && _target)
        {
            [self willChangeValueForKey:@"target"];
            _target = nil;
            [self didChangeValueForKey:@"target"];
        }

        [self didChangeValueForKey:@"actionHandler"];
    }
}

- (id)target
{
    id strongTarget = _target;

    @synchronized (self)
    {
        return strongTarget != nil ? strongTarget : NSApplication.sharedApplication;
    }
}

- (void)setTarget:(id)newTarget
{
    @synchronized (self)
    {
        id strongTarget = _target;

        if (newTarget == strongTarget)
            return;

        strongTarget = newTarget;

        [self willChangeValueForKey:@"target"];
        _target = strongTarget;

        if (strongTarget && _actionHandler)
        {
            [self willChangeValueForKey:@"actionHandler"];
            _actionHandler = nil;
            [self didChangeValueForKey:@"actionHandler"];
        }

        [self didChangeValueForKey:@"target"];
    }
}

#pragma mark Methods

- (BOOL)performActionOnTarget:(id)aTarget
{
    __block BOOL isPerformed = NO;

    os_activity_initiate("-[SRShortcutAction performActionOnTarget:]", OS_ACTIVITY_FLAG_DEFAULT, ^{
        if (!self.isEnabled)
        {
            os_trace_debug("Not performed: disabled");
            return;
        }

        SRShortcutActionHandler actionHandler = self.actionHandler;

        if (actionHandler)
        {
            os_trace_debug("Using action handler");
            isPerformed = actionHandler(self);
        }
        else
        {
            id target = aTarget != nil ? aTarget : self.target;
            if (!target)
            {
                os_trace_debug("Not performed: no associated target");
                return;
            }

            SEL action = self.action;
            
            BOOL canPerformAction = NO;
            BOOL canPerformProtocol = NO;
            if (!(canPerformAction = action && [target respondsToSelector:action]) && !(canPerformProtocol = [target respondsToSelector:@selector(performShortcutAction:)]))
            {
                os_trace_debug("Not performed: target cannot respond to action");
                return;
            }
            else if ([target respondsToSelector:@selector(validateUserInterfaceItem:)] && ![target validateUserInterfaceItem:self])
            {
                os_trace_debug("Not performed: target ignored action");
                return;
            }

            if (canPerformAction)
            {
                os_trace_debug("Using action");
                NSMethodSignature *sig = [target methodSignatureForSelector:action];
                IMP actionMethod = [target methodForSelector:action];
                BOOL returnsBool = strncmp(sig.methodReturnType, @encode(BOOL), 2) == 0;
                switch (sig.numberOfArguments)
                {
                    case 2:
                    {
                        if (returnsBool)
                            isPerformed = ((BOOL (*)(id, SEL))actionMethod)(target, action);
                        else
                        {
                            ((void (*)(id, SEL))actionMethod)(target, action);
                            isPerformed = YES;
                        }
                        break;
                    }
                    case 3:
                    {
                        if (returnsBool)
                            isPerformed = ((BOOL (*)(id, SEL, id))actionMethod)(target, action, self);
                        else
                        {
                            ((void (*)(id, SEL, id))actionMethod)(target, action, self);
                            isPerformed = YES;
                        }
                        break;
                    }
                    default:
                        break;
                }
            }
            else if (canPerformProtocol)
            {
                os_trace_debug("Using protocol");
                isPerformed = [(id<SRShortcutActionTarget>)target performShortcutAction:self];
            }
        }
    });

    return isPerformed;
}

#pragma mark Private

- (void)_invalidateObserving
{
    id strongObservedObject = _observedObject;

    if (strongObservedObject)
        [strongObservedObject removeObserver:self forKeyPath:_observedKeyPath context:_SRShortcutActionContext];

    _observedObject = nil;
    _observedKeyPath = nil;
}

#pragma mark NSObject

- (void)observeValueForKeyPath:(NSString *)aKeyPath
                      ofObject:(NSObject *)anObject
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)aChange
                       context:(void *)aContext
{
    if (aContext != _SRShortcutActionContext)
    {
        [super observeValueForKeyPath:aKeyPath ofObject:anObject change:aChange context:aContext];
        return;
    }

    os_activity_initiate("-[SRShortcutAction observeValueForKeyPath:ofObject:change:context:]", OS_ACTIVITY_FLAG_DEFAULT, ^{
        SRShortcut *newShortcut = aChange[NSKeyValueChangeNewKey];

        // NSController subclasses are notable for not setting the New and Old keys of the change dictionary.
        if ((!newShortcut || (NSNull *)newShortcut == NSNull.null) && [anObject isKindOfClass:NSController.class])
            newShortcut = [anObject valueForKeyPath:aKeyPath];

        if ([newShortcut isKindOfClass:NSDictionary.class])
            newShortcut = [SRShortcut shortcutWithDictionary:(NSDictionary *)newShortcut];
        else if ([newShortcut isKindOfClass:NSData.class])
            newShortcut = [NSKeyedUnarchiver unarchiveObjectWithData:(NSData *)newShortcut];
        else if ((NSNull *)newShortcut == NSNull.null)
            newShortcut = nil;

        @synchronized (self)
        {
            if (self->_shortcut == newShortcut || [self->_shortcut isEqual:newShortcut])
                return;

            [self willChangeValueForKey:@"shortcut"];
            self->_shortcut = newShortcut;
            [self didChangeValueForKey:@"shortcut"];
        }
    });
}

@end


#pragma mark -


@implementation NSEvent (SRShortcutAction)

- (SRKeyEventType)SR_keyEventType
{
    SRKeyEventType eventType = 0;

    switch (self.type)
    {
        case NSEventTypeKeyDown:
            eventType = SRKeyEventTypeDown;
            break;
        case NSEventTypeKeyUp:
            eventType = SRKeyEventTypeUp;
            break;
        case NSEventTypeFlagsChanged:
        {
            __auto_type keyCode = self.keyCode;
            if (keyCode == kVK_Command || keyCode == kVK_RightCommand)
                eventType = self.modifierFlags & NSEventModifierFlagCommand ? SRKeyEventTypeDown : SRKeyEventTypeUp;
            else if (keyCode == kVK_Option || keyCode == kVK_RightOption)
                eventType = self.modifierFlags & NSEventModifierFlagOption ? SRKeyEventTypeDown : SRKeyEventTypeUp;
            else if (keyCode == kVK_Shift || keyCode == kVK_RightShift)
                eventType = self.modifierFlags & NSEventModifierFlagShift ? SRKeyEventTypeDown : SRKeyEventTypeUp;
            else if (keyCode == kVK_Control || keyCode == kVK_RightControl)
                eventType = self.modifierFlags & NSEventModifierFlagControl ? SRKeyEventTypeDown : SRKeyEventTypeUp;
            else
                os_trace("#Error Unexpected key code %hu for the FlagsChanged event", keyCode);
            break;
        }
        default:
            os_trace("#Error Unexpected key event of type %lu", self.type);
            break;
    }

    return eventType;
}

@end


static void *_SRShortcutMonitorContext = &_SRShortcutMonitorContext;


@interface SRShortcutMonitor ()
{
    @protected
    NSCountedSet<SRShortcutAction *> *_actions;
    NSMutableSet<SRShortcutAction *> *_enabledActions;
    NSMutableSet<SRShortcutAction *> *_keyUpActions;
    NSMutableSet<SRShortcutAction *> *_keyDownActions;
    NSMutableDictionary<SRShortcut *, NSMutableOrderedSet<SRShortcutAction *> *> *_shortcutToEnabledKeyDownActions;
    NSMutableDictionary<SRShortcut *, NSMutableOrderedSet<SRShortcutAction *> *> *_shortcutToEnabledKeyUpActions;
    NSCountedSet<SRShortcut *> *_shortcuts; // count increased for every enabled action
}
@end


@implementation SRShortcutMonitor

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _actions = [NSCountedSet new];
        _enabledActions = [NSMutableSet new];
        _shortcutToEnabledKeyDownActions = [NSMutableDictionary new];
        _shortcutToEnabledKeyUpActions = [NSMutableDictionary new];
        _keyUpActions = [NSMutableSet new];
        _keyDownActions = [NSMutableSet new];
        _shortcuts = [NSCountedSet new];
    }

    return self;
}

- (void)dealloc
{
    for (SRShortcutAction *a in _actions)
        [a removeObserver:self forKeyPath:@"enabled" context:_SRShortcutMonitorContext];

    for (SRShortcutAction *a in _enabledActions)
        [a removeObserver:self forKeyPath:@"shortcut" context:_SRShortcutMonitorContext];
}

#pragma mark Properties

- (NSArray<SRShortcutAction *> *)actions
{
    @synchronized (_actions)
    {
        return _actions.allObjects;
    }
}

- (NSArray<SRShortcut *> *)shortcuts
{
    @synchronized (_actions)
    {
        return _shortcuts.allObjects;
    }
}

#pragma mark Methods

- (NSArray<SRShortcutAction *> *)actionsForKeyEvent:(SRKeyEventType)aKeyEvent
{
    @synchronized (_actions)
    {
        return [self _actionsForKeyEvent:aKeyEvent].allObjects;
    }
}

- (NSArray<SRShortcutAction *> *)enabledActionsForShortcut:(SRShortcut *)aShortcut keyEvent:(SRKeyEventType)aKeyEvent
{
    @synchronized (_actions)
    {
        __auto_type result = [self _enabledActionsForShortcut:aShortcut keyEvent:aKeyEvent];
        return result != nil ? [NSArray arrayWithArray:result.array] : [NSArray new];
    }
}

- (void)addAction:(SRShortcutAction *)anAction forKeyEvent:(SRKeyEventType)aKeyEvent
{
    @synchronized (_actions)
    {
        NSAssert([_actions countForObject:anAction] < 2, @"Action is added too many times");

        __auto_type keyEventActions = [self _actionsForKeyEvent:aKeyEvent];
        BOOL isFirstActionForKeyEvent = ![keyEventActions containsObject:anAction];

        if (isFirstActionForKeyEvent)
        {
            BOOL isFirstAction = ![_actions countForObject:anAction];

            if (isFirstAction)
                [self willChangeValueForKey:@"actions"];

            [_actions addObject:anAction];
            [keyEventActions addObject:anAction];

            if (isFirstAction)
            {
                [anAction addObserver:self
                           forKeyPath:@"enabled"
                              options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionInitial
                              context:_SRShortcutMonitorContext];
            }
            else if ([_enabledActions containsObject:anAction])
            {
                __auto_type shortcut = [self _shortcutForEnabledAction:anAction hint:nil];
                [self _addEnabledAction:anAction toShortcut:shortcut forKeyEvent:aKeyEvent];
            }

            if (isFirstAction)
                [self didChangeValueForKey:@"actions"];
        }
        else if (anAction.shortcut)
        {
            __auto_type shortcutActions = [self _enabledActionsForShortcut:anAction.shortcut keyEvent:aKeyEvent];
            NSAssert(shortcutActions.count, @"Action was not added to the shortcut");
            NSUInteger fromIndex = [shortcutActions indexOfObject:anAction];
            NSAssert(fromIndex != NSNotFound, @"Action was not added to the shortcut");
            [shortcutActions moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:fromIndex] toIndex:shortcutActions.count - 1];
        }
    }
}

- (void)removeAction:(SRShortcutAction *)anAction forKeyEvent:(SRKeyEventType)aKeyEvent
{
    @synchronized (_actions)
    {
        __auto_type keyEventActions = [self _actionsForKeyEvent:aKeyEvent];
        if (![keyEventActions containsObject:anAction])
            return;

        BOOL isLastAction = [_actions countForObject:anAction] == 1;

        if (isLastAction)
        {
            [self willChangeValueForKey:@"actions"];
            [anAction removeObserver:self forKeyPath:@"enabled" context:_SRShortcutMonitorContext];
        }

        BOOL isLastActionForShortcut = NO;
        SRShortcut *shortcut = nil;

        if ([_enabledActions containsObject:anAction])
        {
            if (isLastAction)
                [anAction removeObserver:self forKeyPath:@"shortcut" context:_SRShortcutMonitorContext];

            shortcut = [self _shortcutForEnabledAction:anAction hint:nil];
            isLastActionForShortcut = [_shortcuts countForObject:shortcut] == 1;

            if (isLastActionForShortcut)
            {
                [self willChangeValueForKey:@"shortcuts"];
                [self willRemoveShortcut:shortcut];
            }

            [self _removeEnabledAction:anAction fromShortcut:shortcut forKeyEvent:aKeyEvent];

            if (isLastAction)
                [_enabledActions removeObject:anAction];
        }

        [keyEventActions removeObject:anAction];
        [_actions removeObject:anAction];

        if (isLastActionForShortcut)
        {
            [self didRemoveShortcut:shortcut];
            [self didChangeValueForKey:@"shortcuts"];
        }

        if (isLastAction)
            [self didChangeValueForKey:@"actions"];
    }
}

- (void)removeAction:(SRShortcutAction *)anAction
{
    @synchronized (_actions)
    {
        [self removeAction:anAction forKeyEvent:SRKeyEventTypeDown];
        [self removeAction:anAction forKeyEvent:SRKeyEventTypeUp];
    }
}

- (void)removeAllActions
{
    @synchronized (_actions)
    {
        for (SRShortcutAction *a in _actions)
            [a removeObserver:self forKeyPath:@"enabled" context:_SRShortcutMonitorContext];

        for (SRShortcutAction *a in _enabledActions)
            [a removeObserver:self forKeyPath:@"shortcut" context:_SRShortcutMonitorContext];

        [self willChangeValueForKey:@"actions"];
        [self willChangeValueForKey:@"shortcuts"];

        __auto_type oldShortcuts = _shortcuts.allObjects;
        for (SRShortcut *s in oldShortcuts)
            [self willRemoveShortcut:s];

        _shortcuts = [NSCountedSet new];
        [_actions removeAllObjects];
        [_enabledActions removeAllObjects];
        [_keyUpActions removeAllObjects];
        [_keyDownActions removeAllObjects];
        [_shortcutToEnabledKeyDownActions removeAllObjects];
        [_shortcutToEnabledKeyUpActions removeAllObjects];

        [oldShortcuts enumerateObjectsWithOptions:NSEnumerationReverse
                                       usingBlock:^(SRShortcut * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop)
        {
            [self didRemoveShortcut:obj];
        }];

        [self didChangeValueForKey:@"shortcuts"];
        [self didChangeValueForKey:@"actions"];
    }
}

- (void)willAddShortcut:(SRShortcut *)aShortcut
{
}

- (void)didAddShortcut:(SRShortcut *)aShortcut
{
}

- (void)willRemoveShortcut:(SRShortcut *)aShortcut
{
}

- (void)didRemoveShortcut:(SRShortcut *)aShortcut
{
}

#pragma mark Private

- (NSMutableSet<SRShortcutAction *> *)_actionsForKeyEvent:(SRKeyEventType)aKeyEvent
{
    switch (aKeyEvent)
    {
        case SRKeyEventTypeDown:
            return _keyDownActions;
        case SRKeyEventTypeUp:
            return _keyUpActions;
        default:
            [NSException raise:NSInvalidArgumentException format:@"Unexpected keyboard event type %lu", aKeyEvent];
            return nil;
    }
}

- (NSMutableDictionary<SRShortcut *, NSMutableOrderedSet<SRShortcutAction *> *> *)_shortcutToEnabledActionsForKeyEvent:(SRKeyEventType)aKeyEvent
{
    switch (aKeyEvent)
    {
        case SRKeyEventTypeDown:
            return _shortcutToEnabledKeyDownActions;
        case SRKeyEventTypeUp:
            return _shortcutToEnabledKeyUpActions;
        default:
            [NSException raise:NSInvalidArgumentException format:@"Unexpected keyboard event type %lu", aKeyEvent];
            return nil;
    }
}

- (nullable NSMutableOrderedSet<SRShortcutAction *> *)_enabledActionsForShortcut:(nonnull SRShortcut *)aShortcut
                                                                        keyEvent:(SRKeyEventType)aKeyEvent
{
    return [[self _shortcutToEnabledActionsForKeyEvent:aKeyEvent] objectForKey:aShortcut];
}

- (nonnull SRShortcut *)_shortcutForEnabledAction:(nonnull SRShortcutAction *)anAction hint:(nullable SRShortcut *)aShortcut
{
    NSParameterAssert([_enabledActions containsObject:anAction]);

    __auto_type checkShortcut = ^(SRShortcut * _Nullable aShortcut) {
        if (!aShortcut)
            return NO;

        if (self->_shortcutToEnabledKeyDownActions[aShortcut] != nil &&
            [self->_shortcutToEnabledKeyDownActions[aShortcut] containsObject:anAction])
        {
            return YES;
        }
        else if (self->_shortcutToEnabledKeyUpActions[aShortcut] != nil &&
                 [self->_shortcutToEnabledKeyUpActions[aShortcut] containsObject:anAction])
        {
            return YES;
        }

        return NO;
    };

    if (checkShortcut(aShortcut))
        return aShortcut;
    else if (checkShortcut(anAction.shortcut))
        return anAction.shortcut;
    else
    {
        for (SRShortcut *s in _shortcuts)
        {
            if (checkShortcut(s))
                return s;
        }
    }

    __builtin_unreachable();
}

- (void)_enabledActionDidChangeShortcut:(nonnull SRShortcutAction *)anAction
                                   from:(nullable SRShortcut *)anOldShortcut
                                     to:(nullable SRShortcut *)aNewShortcut
{
    NSParameterAssert(![anOldShortcut isEqual:aNewShortcut]);

    BOOL isKeyDownAction = [_keyDownActions containsObject:anAction];
    BOOL isKeyUpAction = [_keyUpActions containsObject:anAction];
    BOOL isLastActionForOldShortcut = anOldShortcut && [_shortcuts countForObject:anOldShortcut] == 1;
    BOOL isFirstActionForNewShortcut = aNewShortcut && [_shortcuts countForObject:aNewShortcut] == 0;

    if (isLastActionForOldShortcut || isFirstActionForNewShortcut)
        [self willChangeValueForKey:@"shortcuts"];

    if (isLastActionForOldShortcut)
        [self willRemoveShortcut:anOldShortcut];

    if (anOldShortcut)
    {
        if (isKeyDownAction)
            [self _removeEnabledAction:anAction fromShortcut:anOldShortcut forKeyEvent:SRKeyEventTypeDown];

        if (isKeyUpAction)
            [self _removeEnabledAction:anAction fromShortcut:anOldShortcut forKeyEvent:SRKeyEventTypeUp];
    }

    if (isLastActionForOldShortcut)
        [self didRemoveShortcut:anOldShortcut];

    if (isFirstActionForNewShortcut)
        [self willAddShortcut:aNewShortcut];

    if (aNewShortcut)
    {
        if (isKeyDownAction)
            [self _addEnabledAction:anAction toShortcut:aNewShortcut forKeyEvent:SRKeyEventTypeDown];

        if (isKeyUpAction)
            [self _addEnabledAction:anAction toShortcut:aNewShortcut forKeyEvent:SRKeyEventTypeUp];
    }

    if (isFirstActionForNewShortcut)
        [self didAddShortcut:aNewShortcut];

    if (isLastActionForOldShortcut || isFirstActionForNewShortcut)
        [self didChangeValueForKey:@"shortcuts"];
}

- (void)_addEnabledAction:(nonnull SRShortcutAction *)anAction
               toShortcut:(nonnull SRShortcut *)aShortcut
              forKeyEvent:(SRKeyEventType)aKeyEvent
{
    __auto_type shortcutToActions = [self _shortcutToEnabledActionsForKeyEvent:aKeyEvent];
    __auto_type actions = shortcutToActions[aShortcut];
    NSParameterAssert(![actions containsObject:anAction]);

    [_shortcuts addObject:aShortcut];

    if (!actions)
    {
        actions = [NSMutableOrderedSet orderedSetWithObject:anAction];
        shortcutToActions[aShortcut] = actions;
    }
    else
        [actions addObject:anAction];
}

- (void)_removeEnabledAction:(nonnull SRShortcutAction *)anAction
                fromShortcut:(SRShortcut *)aShortcut
                 forKeyEvent:(SRKeyEventType)aKeyEvent
{
    __auto_type shortcutToActions = [self _shortcutToEnabledActionsForKeyEvent:aKeyEvent];
    __auto_type actions = shortcutToActions[aShortcut];
    NSParameterAssert([actions containsObject:anAction]);

    [_shortcuts removeObject:aShortcut];
    [actions removeObject:anAction];

    if (!actions.count)
        shortcutToActions[aShortcut] = nil;
}

#pragma mark NSObject

- (void)observeValueForKeyPath:(NSString *)aKeyPath
                      ofObject:(NSObject *)anObject
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)aChange
                       context:(void *)aContext
{
    if (aContext == _SRShortcutMonitorContext)
    {
        __auto_type action = (SRShortcutAction *)anObject;

        if ([aKeyPath isEqualToString:@"enabled"])
        {
            BOOL wasEnabled = [aChange[NSKeyValueChangeOldKey] boolValue]; // NO for NSKeyValueObservingOptionInitial
            BOOL isEnabled = [aChange[NSKeyValueChangeNewKey] boolValue];

            if (wasEnabled == isEnabled)
                return;

            if (isEnabled)
            {
                [_enabledActions addObject:action];
                [action addObserver:self
                         forKeyPath:@"shortcut"
                            options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionInitial
                            context:_SRShortcutMonitorContext];
            }
            else
            {
                [action removeObserver:self forKeyPath:@"shortcut" context:_SRShortcutMonitorContext];

                @synchronized (_actions)
                {
                    __auto_type shortcut = [self _shortcutForEnabledAction:action hint:nil];
                    BOOL isLastActionForShortcut = [_shortcuts countForObject:shortcut] == 1;

                    if (isLastActionForShortcut)
                    {
                        [self willChangeValueForKey:@"shortcuts"];
                        [self willRemoveShortcut:shortcut];
                    }

                    if ([_keyDownActions containsObject:action])
                        [self _removeEnabledAction:action fromShortcut:shortcut forKeyEvent:SRKeyEventTypeDown];

                    if ([_keyUpActions containsObject:action])
                        [self _removeEnabledAction:action fromShortcut:shortcut forKeyEvent:SRKeyEventTypeUp];

                    if (isLastActionForShortcut)
                    {
                        [self didRemoveShortcut:shortcut];
                        [self didChangeValueForKey:@"shortcuts"];
                    }

                    [_enabledActions removeObject:action];
                }
            }
        }
        else if ([aKeyPath isEqualToString:@"shortcut"])
        {
            SRShortcut *oldShortcut = aChange[NSKeyValueChangeOldKey]; // nil for NSKeyValueObservingOptionInitial
            SRShortcut *newShortcut = aChange[NSKeyValueChangeNewKey];

            if ([oldShortcut isEqual:newShortcut])
                return;

            @synchronized (_actions)
            {
                [self _enabledActionDidChangeShortcut:action
                                                 from:((id)oldShortcut == NSNull.null) ? nil : oldShortcut
                                                   to:((id)newShortcut == NSNull.null) ? nil : newShortcut];
            }
        }
    }
    else
        [super observeValueForKeyPath:aKeyPath ofObject:anObject change:aChange context:aContext];
}

- (NSString *)debugDescription
{
    NSMutableString *d = [NSMutableString new];
    __auto_type formatActions = ^(NSMutableDictionary<SRShortcut *, NSMutableOrderedSet<SRShortcutAction *> *> *aShortcutToActions) {
        for (SRShortcut *s in aShortcutToActions)
        {
            [d appendFormat:@"\t%@: {\n", s];

            for (SRShortcutAction *a in aShortcutToActions[s])
                [d appendFormat:@"\t\t%@\n", a];

            [d appendString:@"\t}\n"];
        }
    };

    if (_shortcutToEnabledKeyDownActions.count)
    {
        [d appendString:@"Key Down Shortcuts: {\n"];
        formatActions(_shortcutToEnabledKeyDownActions);
        [d appendString:@"}\n"];
    }

    if (_shortcutToEnabledKeyUpActions.count)
    {
        [d appendString:@"Key Up Shortcuts: {\n"];
        formatActions(_shortcutToEnabledKeyUpActions);
        [d appendString:@"}\n"];
    }

    if (d.length)
        return d;
    else
        return @"No Shortcuts";
}

@end


@implementation SRShortcutMonitor (SRShortcutMonitorConveniences)

- (SRShortcutAction *)addAction:(SEL)anAction forKeyEquivalent:(NSString *)aKeyEquivalent tag:(NSInteger)aTag
{
    SRShortcut *shortcut = [SRShortcut shortcutWithKeyEquivalent:aKeyEquivalent];

    if (!shortcut)
        return nil;

    SRShortcutAction *action = [SRShortcutAction shortcutActionWithShortcut:shortcut target:nil action:anAction tag:aTag];
    [self addAction:action forKeyEvent:SRKeyEventTypeDown];
    return action;
}

@end


const OSType SRShortcutActionSignature = 'SRSR';

static const UInt32 _SRInvalidHotKeyID = 0;


@implementation SRGlobalShortcutMonitor
{
    NSMutableDictionary<NSNumber *, SRShortcut *> *_hotKeyIdToShortcut;
    NSMapTable<SRShortcut *, id> *_shortcutToHotKeyRef;
    NSMutableDictionary<SRShortcut *, NSNumber *> *_shortcutToHotKeyId;
    EventHandlerRef _carbonEventHandler;
    NSInteger _disableCounter;
}

static OSStatus _SRCarbonEventHandler(EventHandlerCallRef aHandler, EventRef anEvent, void *aUserData)
{
    if (!anEvent)
    {
        os_trace_error("#Error Event is NULL");
        return eventNotHandledErr;
    }
    else if (GetEventClass(anEvent) != kEventClassKeyboard)
    {
        os_trace_error("#Error Not a keyboard event");
        return eventNotHandledErr;
    }
    else
        return [(__bridge SRGlobalShortcutMonitor *)aUserData handleEvent:anEvent];
}

+ (SRGlobalShortcutMonitor *)sharedMonitor
{
    static SRGlobalShortcutMonitor *Shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Shared = [SRGlobalShortcutMonitor new];
    });
    return Shared;
}

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _hotKeyIdToShortcut = [NSMutableDictionary new];
        _shortcutToHotKeyRef = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality
                                                     valueOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality];
        _shortcutToHotKeyId = [NSMutableDictionary new];
    }

    return self;
}

- (void)dealloc
{
    for (SRShortcut *shortcut in _shortcuts)
        [self _unregisterHotKeyForShortcutIfNeeded:shortcut];

    [self _removeEventHandlerIfNeeded];
}

#pragma mark Methods

- (void)resume
{
    @synchronized (_actions)
    {
        os_trace_debug("Global Shortcut Monitor counter: %ld -> %ld", _disableCounter, _disableCounter - 1);
        _disableCounter -= 1;

        if (_disableCounter == 0)
        {
            for (SRShortcut *shortcut in _shortcuts)
                [self _registerHotKeyForShortcutIfNeeded:shortcut];
        }

        [self _installEventHandlerIfNeeded];
    }
}

- (void)pause
{
    @synchronized (_actions)
    {
        os_trace_debug("Global Shortcut Monitor counter: %ld -> %ld", _disableCounter, _disableCounter + 1);
        _disableCounter += 1;

        if (_disableCounter == 1)
        {
            for (SRShortcut *shortcut in _shortcuts)
                [self _unregisterHotKeyForShortcutIfNeeded:shortcut];
        }

        [self _removeEventHandlerIfNeeded];
    }
}

- (OSStatus)handleEvent:(EventRef)anEvent
{
    __block OSStatus error = eventNotHandledErr;

    os_activity_initiate("-[SRGlobalShortcutMonitor handleEvent:]", OS_ACTIVITY_FLAG_DETACHED, ^{
        if (self->_disableCounter > 0)
        {
            os_trace_debug("Monitoring is currently disabled");
            return;
        }

        EventHotKeyID hotKeyID;
        if (GetEventParameter(anEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID) != noErr)
        {
            os_trace_error("#Critical Failed to get hot key ID: %d", error);
            return;
        }
        else if (hotKeyID.id == 0 || hotKeyID.signature != SRShortcutActionSignature)
        {
            os_trace_error("#Error Unexpected hot key with id %u and signature: %u", hotKeyID.id, hotKeyID.signature);
            return;
        }

        @synchronized (self->_actions)
        {
            SRShortcut *shortcut = [self->_hotKeyIdToShortcut objectForKey:@(hotKeyID.id)];

            if (!shortcut)
            {
                os_trace("Unregistered hot key with id %u and signature %u", hotKeyID.id, hotKeyID.signature);
                return;
            }

            SRKeyEventType eventType = 0;
            switch (GetEventKind(anEvent))
            {
                case kEventHotKeyPressed:
                    eventType = SRKeyEventTypeDown;
                    break;
                case kEventHotKeyReleased:
                    eventType = SRKeyEventTypeUp;
                    break;
                default:
                    os_trace("#Error Unexpected key event of type %u", GetEventKind(anEvent));
                    return;
            }

            __auto_type actions = [self enabledActionsForShortcut:shortcut keyEvent:eventType];

            if (!actions.count)
            {
                os_trace("No actions for the shortcut");
                return;
            }

            __block BOOL isHandled = NO;

            [actions enumerateObjectsWithOptions:NSEnumerationReverse
                                      usingBlock:^(SRShortcutAction *obj, NSUInteger idx, BOOL *stop)
            {
                *stop = isHandled = [obj performActionOnTarget:nil];
            }];

            if (isHandled)
                error = noErr;
        }
    });

    return error;
}

- (void)didAddEventHandler
{
    os_trace_debug("Added Carbon HotKey Event Handler");
}

- (void)didRemoveEventHandler
{
    os_trace_debug("Removed Carbon HotKey Event Handler");
}

#pragma mark Private

- (void)_installEventHandlerIfNeeded
{
    if (_carbonEventHandler)
        return;

    if (_disableCounter > 0 || !_shortcutToHotKeyRef.count)
        return;

    static const EventTypeSpec EventSpec[] = {
        { kEventClassKeyboard, kEventHotKeyPressed },
        { kEventClassKeyboard, kEventHotKeyReleased }
    };
    os_trace("Installing Carbon hot key event handler");
    OSStatus error = InstallEventHandler(GetEventDispatcherTarget(),
                                         _SRCarbonEventHandler,
                                         sizeof(EventSpec) / sizeof(EventTypeSpec),
                                         EventSpec,
                                         (__bridge void *)self,
                                         &_carbonEventHandler);

    if (error != noErr)
    {
        os_trace_error("#Critical Failed to install event handler: %d", error);
        _carbonEventHandler = NULL;
    }
    else
        [self didAddEventHandler];
}

- (void)_removeEventHandlerIfNeeded
{
    if (!_carbonEventHandler)
        return;

    if (_disableCounter <= 0 && _shortcutToHotKeyRef.count)
        return;

    os_trace("Removing Carbon hot key event handler");
    OSStatus error = RemoveEventHandler(_carbonEventHandler);

    if (error != noErr)
        os_trace_error("#Error Failed to remove event handler: %d", error);

    // Assume that an error happened due to _carbonEventHandler being invalid.
    _carbonEventHandler = NULL;
    [self didRemoveEventHandler];
}

- (void)_registerHotKeyForShortcutIfNeeded:(SRShortcut *)aShortcut
{
    EventHotKeyRef hotKey = (__bridge EventHotKeyRef)([_shortcutToHotKeyRef objectForKey:aShortcut]);

    if (hotKey)
        return;

    if (aShortcut.keyCode == SRKeyCodeNone)
    {
        os_trace_error("#Error Shortcut without a key code cannot be registered as Carbon hot key");
        return;
    }

    static UInt32 CarbonID = _SRInvalidHotKeyID;
    EventHotKeyID hotKeyID = {SRShortcutActionSignature, ++CarbonID};
    os_trace("Registering Carbon hot key");
    OSStatus error = RegisterEventHotKey(aShortcut.carbonKeyCode,
                                         aShortcut.carbonModifierFlags,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         kEventHotKeyNoOptions,
                                         &hotKey);

    if (error != noErr || !hotKey)
    {
        os_trace_error_with_payload("#Critical Failed to register Carbon hot key: %d", error, ^(xpc_object_t d) {
            xpc_dictionary_set_uint64(d, "keyCode", aShortcut.keyCode);
            xpc_dictionary_set_uint64(d, "modifierFlags", aShortcut.modifierFlags);
        });
        return;
    }

    os_trace_with_payload("Registered Carbon hot key %u", hotKeyID.id, ^(xpc_object_t d) {
        xpc_dictionary_set_uint64(d, "keyCode", aShortcut.keyCode);
        xpc_dictionary_set_uint64(d, "modifierFlags", aShortcut.modifierFlags);
    });

    [_shortcutToHotKeyRef setObject:(__bridge id _Nullable)(hotKey) forKey:aShortcut];
    [_hotKeyIdToShortcut setObject:aShortcut forKey:@(hotKeyID.id)];
    [_shortcutToHotKeyId setObject:@(hotKeyID.id) forKey:aShortcut];
}

- (void)_unregisterHotKeyForShortcutIfNeeded:(SRShortcut *)aShortcut
{
    EventHotKeyRef hotKey = (__bridge EventHotKeyRef)([_shortcutToHotKeyRef objectForKey:aShortcut]);

    if (!hotKey)
        return;

    UInt32 hotKeyID = [_shortcutToHotKeyId objectForKey:aShortcut].unsignedIntValue;

    os_trace("Removing Carbon hot key %u", hotKeyID);
    OSStatus error = UnregisterEventHotKey(hotKey);

    if (error != noErr)
    {
        os_trace_error_with_payload("#Critical Failed to unregister Carbon hot key %u: %d", hotKeyID, error, ^(xpc_object_t d) {
            xpc_dictionary_set_uint64(d, "keyCode", aShortcut.keyCode);
            xpc_dictionary_set_uint64(d, "modifierFlags", aShortcut.modifierFlags);
        });
    }
    else
    {
        os_trace_with_payload("Unregistered Carbon hot key %u", hotKeyID, ^(xpc_object_t d) {
            xpc_dictionary_set_uint64(d, "keyCode", aShortcut.keyCode);
            xpc_dictionary_set_uint64(d, "modifierFlags", aShortcut.modifierFlags);
        });
    }

    // Assume that an error to unregister the handler is due to the latter being invalid.
    [_shortcutToHotKeyRef removeObjectForKey:aShortcut];
    [_shortcutToHotKeyId removeObjectForKey:aShortcut];
    [_hotKeyIdToShortcut removeObjectForKey:@(hotKeyID)];
}

#pragma mark SRShortcutMonitor

- (void)didAddShortcut:(SRShortcut *)aShortcut
{
    [self _registerHotKeyForShortcutIfNeeded:aShortcut];
    [self _installEventHandlerIfNeeded];
}

- (void)willRemoveShortcut:(SRShortcut *)aShortcut
{
    [self _unregisterHotKeyForShortcutIfNeeded:aShortcut];
    [self _removeEventHandlerIfNeeded];
}

@end


@implementation SRAXGlobalShortcutMonitor

CGEventRef _Nullable _SRQuartzEventHandler(CGEventTapProxy aProxy, CGEventType aType, CGEventRef anEvent, void * _Nullable aUserInfo)
{
    __auto_type self = (__bridge SRAXGlobalShortcutMonitor *)aUserInfo;

    if (aType == kCGEventTapDisabledByTimeout || aType == kCGEventTapDisabledByUserInput)
    {
        os_trace("#Error #Developer The system disabled event tap due to %u", aType);
        CGEventTapEnable(self.eventTap, true);
        return anEvent;
    }
    else if (aType != kCGEventKeyDown && aType != kCGEventKeyUp && aType != kCGEventFlagsChanged)
    {
        os_trace("#Error #Developer Unexpected event of type %u", aType);
        return anEvent;
    }
    else
        return [self handleEvent:anEvent];
}

- (instancetype)init
{
    return [self initWithRunLoop:NSRunLoop.currentRunLoop];
}

- (instancetype)initWithRunLoop:(NSRunLoop *)aRunLoop
{
    static const CGEventMask Mask = (CGEventMaskBit(kCGEventKeyDown) |
                                     CGEventMaskBit(kCGEventKeyUp) |
                                     CGEventMaskBit(kCGEventFlagsChanged));
    __auto_type eventTap = CGEventTapCreate(kCGSessionEventTap,
                                            kCGHeadInsertEventTap,
                                            kCGEventTapOptionDefault,
                                            Mask,
                                            _SRQuartzEventHandler,
                                            (__bridge void *)self);
    if (!eventTap)
    {
        os_trace_error("#Critical Unable to create event tap: make sure Accessibility is enabled");
        return nil;
    }

    self = [super init];

    if (self)
    {
        _eventTap = eventTap;
        _eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        CFRunLoopAddSource(aRunLoop.getCFRunLoop, _eventTapSource, kCFRunLoopDefaultMode);
    }

    return self;
}

- (void)dealloc
{
    if (_eventTap)
        CFRelease(_eventTap);

    CFRelease(_eventTapSource);
}

#pragma mark Methods

- (CGEventRef)handleEvent:(CGEventRef)anEvent
{
    __block __auto_type result = anEvent;

    os_activity_initiate("-[SRAXGlobalShortcutMonitor handleEvent:]", OS_ACTIVITY_FLAG_DETACHED, ^{
        __auto_type nsEvent = [NSEvent eventWithCGEvent:anEvent];
        if (!nsEvent)
        {
            os_trace_error("#Error Unexpected event");
            return;
        }

        __auto_type shortcut = [SRShortcut shortcutWithEvent:nsEvent];
        if (!shortcut)
        {
            os_trace_error("#Error Not a keyboard event");
            return;
        }

        SRKeyEventType eventType = nsEvent.SR_keyEventType;
        if (eventType == 0)
            return;

        __auto_type actions = [self enabledActionsForShortcut:shortcut keyEvent:eventType];
        __block BOOL isHandled = NO;
        [actions enumerateObjectsWithOptions:NSEnumerationReverse
                                  usingBlock:^(SRShortcutAction *obj, NSUInteger idx, BOOL *stop)
        {
            *stop = isHandled = [obj performActionOnTarget:nil];
        }];

        result = isHandled ? nil : anEvent;
    });

    return result;
}

#pragma mark SRShortcutMonitor

- (void)didAddShortcut:(SRShortcut *)aShortcut
{
    if (_shortcuts.count)
        CGEventTapEnable(_eventTap, true);
}

- (void)willRemoveShortcut:(SRShortcut *)aShortcut
{
    if (_shortcuts.count == 1 && [_shortcuts countForObject:aShortcut] == 1)
        CGEventTapEnable(_eventTap, false);
}

@end


@interface NSObject (_SRShortcutAction)
- (void)undo:(id)aSender;
- (void)redo:(id)aSender;
@end


@implementation SRLocalShortcutMonitor

+ (SRLocalShortcutMonitor *)standardShortcuts
{
    SRLocalShortcutMonitor *m = [SRLocalShortcutMonitor new];
    [m addAction:@selector(moveForward:) forKeyEquivalent:@"⌃F" tag:0];
    [m addAction:@selector(moveRight:) forKeyEquivalent:@"→" tag:0];
    [m addAction:@selector(moveBackward:) forKeyEquivalent:@"⌃B" tag:0];
    [m addAction:@selector(moveLeft:) forKeyEquivalent:@"←" tag:0];
    [m addAction:@selector(moveUp:) forKeyEquivalent:@"↑" tag:0];
    [m addAction:@selector(moveUp:) forKeyEquivalent:@"⌃P" tag:0];
    [m addAction:@selector(moveDown:) forKeyEquivalent:@"↓" tag:0];
    [m addAction:@selector(moveDown:) forKeyEquivalent:@"⌃N" tag:0];
    [m addAction:@selector(moveWordForward:) forKeyEquivalent:@"⌥F" tag:0];
    [m addAction:@selector(moveWordBackward:) forKeyEquivalent:@"⌥B" tag:0];
    [m addAction:@selector(moveToBeginningOfLine:) forKeyEquivalent:@"⌃A" tag:0];
    [m addAction:@selector(moveToEndOfLine:) forKeyEquivalent:@"⌃E" tag:0];
    [m addAction:@selector(moveToEndOfDocument:) forKeyEquivalent:@"⌘↓" tag:0];
    [m addAction:@selector(moveToBeginningOfDocument:) forKeyEquivalent:@"⌘↑" tag:0];
    [m addAction:@selector(pageDown:) forKeyEquivalent:@"⌃V" tag:0];
    [m addAction:@selector(pageUp:) forKeyEquivalent:@"⌥V" tag:0];
    [m addAction:@selector(centerSelectionInVisibleArea:) forKeyEquivalent:@"⌃L" tag:0];
    [m addAction:@selector(moveBackwardAndModifySelection:) forKeyEquivalent:@"⇧⌃B" tag:0];
    [m addAction:@selector(moveForwardAndModifySelection:) forKeyEquivalent:@"⇧⌃F" tag:0];
    [m addAction:@selector(moveWordForwardAndModifySelection:) forKeyEquivalent:@"⇧⌥F" tag:0];
    [m addAction:@selector(moveWordBackwardAndModifySelection:) forKeyEquivalent:@"⇧⌥B" tag:0];
    [m addAction:@selector(moveUpAndModifySelection:) forKeyEquivalent:@"⇧↑" tag:0];
    [m addAction:@selector(moveUpAndModifySelection:) forKeyEquivalent:@"⇧⌃P" tag:0];
    [m addAction:@selector(moveDownAndModifySelection:) forKeyEquivalent:@"⇧↓" tag:0];
    [m addAction:@selector(moveDownAndModifySelection:) forKeyEquivalent:@"⇧⌃N" tag:0];
    [m addAction:@selector(moveToBeginningOfLineAndModifySelection:) forKeyEquivalent:@"⇧⌃A" tag:0];
    [m addAction:@selector(moveToBeginningOfLineAndModifySelection:) forKeyEquivalent:@"⇧⌘←" tag:0];
    [m addAction:@selector(moveToEndOfLineAndModifySelection:) forKeyEquivalent:@"⇧⌃E" tag:0];
    [m addAction:@selector(moveToEndOfLineAndModifySelection:) forKeyEquivalent:@"⇧⌘→" tag:0];
    [m addAction:@selector(moveToEndOfDocumentAndModifySelection:) forKeyEquivalent:@"⇧⌘↓" tag:0];
    [m addAction:@selector(moveToBeginningOfDocumentAndModifySelection:) forKeyEquivalent:@"⇧⌘↑" tag:0];
    [m addAction:@selector(pageDownAndModifySelection:) forKeyEquivalent:@"⇧⌃V" tag:0];
    [m addAction:@selector(pageUpAndModifySelection:) forKeyEquivalent:@"⇧⌥V" tag:0];
    [m addAction:@selector(moveWordRight:) forKeyEquivalent:@"⌥→" tag:0];
    [m addAction:@selector(moveWordLeft:) forKeyEquivalent:@"⌥←" tag:0];
    [m addAction:@selector(moveRightAndModifySelection:) forKeyEquivalent:@"⇧→" tag:0];
    [m addAction:@selector(moveLeftAndModifySelection:) forKeyEquivalent:@"⇧←" tag:0];
    [m addAction:@selector(moveWordRightAndModifySelection:) forKeyEquivalent:@"⇧⌥→" tag:0];
    [m addAction:@selector(moveWordLeftAndModifySelection:) forKeyEquivalent:@"⇧⌥←" tag:0];
    [m addAction:@selector(moveToLeftEndOfLine:) forKeyEquivalent:@"⌘←" tag:0];
    [m addAction:@selector(moveToRightEndOfLine:) forKeyEquivalent:@"⌘→" tag:0];
    [m addAction:@selector(moveToLeftEndOfLineAndModifySelection:) forKeyEquivalent:@"⇧⌘←" tag:0];
    [m addAction:@selector(moveToRightEndOfLineAndModifySelection:) forKeyEquivalent:@"⇧⌘→" tag:0];
    [m addAction:@selector(scrollPageUp:) forKeyEquivalent:@"⇞" tag:0];
    [m addAction:@selector(scrollPageDown:) forKeyEquivalent:@"⇟" tag:0];
    [m addAction:@selector(scrollToBeginningOfDocument:) forKeyEquivalent:@"↖" tag:0];
    [m addAction:@selector(scrollToEndOfDocument:) forKeyEquivalent:@"↘" tag:0];
    [m addAction:@selector(transpose:) forKeyEquivalent:@"⌃T" tag:0];
    [m addAction:@selector(transposeWords:) forKeyEquivalent:@"⌥T" tag:0];
    [m addAction:@selector(selectAll:) forKeyEquivalent:@"⌘A" tag:0];
    [m addAction:@selector(insertNewline:) forKeyEquivalent:@"⌃O" tag:0];
    [m addAction:@selector(deleteForward:) forKeyEquivalent:@"⌦" tag:0];
    [m addAction:@selector(deleteBackward:) forKeyEquivalent:@"⌫" tag:0];
    [m addAction:@selector(deleteWordForward:) forKeyEquivalent:@"⌥⌦" tag:0];
    [m addAction:@selector(deleteWordBackward:) forKeyEquivalent:@"⌥⌫" tag:0];
    [m addAction:@selector(deleteToEndOfLine:) forKeyEquivalent:@"⌃K" tag:0];
    [m addAction:@selector(deleteToBeginningOfLine:) forKeyEquivalent:@"⌃W" tag:0];
    [m addAction:@selector(yank:) forKeyEquivalent:@"⌃Y" tag:0];
    [m addAction:@selector(setMark:) forKeyEquivalent:@"⌃Space" tag:0];
    [m addAction:@selector(complete:) forKeyEquivalent:@"⌥⎋" tag:0];
    [m addAction:@selector(cancelOperation:) forKeyEquivalent:@"⌘." tag:0];
    [m updateWithCocoaTextKeyBindings];
    return m;
}

+ (SRLocalShortcutMonitor *)mainMenuShortcuts
{
    SRLocalShortcutMonitor *m = [SRLocalShortcutMonitor new];
    [m addAction:@selector(hide:) forKeyEquivalent:@"⌘H" tag: 0];
    [m addAction:@selector(hideOtherApplications:) forKeyEquivalent:@"⌥⌘H" tag: 0];
    [m addAction:@selector(terminate:) forKeyEquivalent:@"⌘Q" tag: 0];
    [m addAction:@selector(newDocument:) forKeyEquivalent:@"⌘N" tag:0];
    [m addAction:@selector(openDocument:) forKeyEquivalent:@"⌘O" tag:0];
    [m addAction:@selector(performClose:) forKeyEquivalent:@"⌘W" tag:0];
    [m addAction:@selector(saveDocument:) forKeyEquivalent:@"⌘S" tag:0];
    [m addAction:@selector(saveDocumentAs:) forKeyEquivalent:@"⇧⌘S" tag:0];
    [m addAction:@selector(revertDocumentToSaved:) forKeyEquivalent:@"⌘R" tag:0];
    [m addAction:@selector(runPageLayout:) forKeyEquivalent:@"⇧⌘P" tag:0];
    [m addAction:@selector(print:) forKeyEquivalent:@"⌘P" tag:0];
    [m addAction:@selector(undo:) forKeyEquivalent:@"⌘Z" tag:0];
    [m addAction:@selector(redo:) forKeyEquivalent:@"⇧⌘Z" tag:0];
    [m addAction:@selector(cut:) forKeyEquivalent:@"⌘X" tag:0];
    [m addAction:@selector(copy:) forKeyEquivalent:@"⌘C" tag:0];
    [m addAction:@selector(paste:) forKeyEquivalent:@"⌘V" tag:0];
    [m addAction:@selector(pasteAsPlainText:) forKeyEquivalent:@"⌥⇧⌘V" tag:0];
    [m addAction:@selector(selectAll:) forKeyEquivalent:@"⌘A" tag:0];
    [m addAction:@selector(performTextFinderAction:) forKeyEquivalent:@"⌘F" tag:NSTextFinderActionShowFindInterface];
    [m addAction:@selector(performTextFinderAction:) forKeyEquivalent:@"⌥⌘F" tag:NSTextFinderActionShowReplaceInterface];
    [m addAction:@selector(performTextFinderAction:) forKeyEquivalent:@"⌘G" tag:NSTextFinderActionNextMatch];
    [m addAction:@selector(performTextFinderAction:) forKeyEquivalent:@"⇧⌘G" tag:NSTextFinderActionPreviousMatch];
    [m addAction:@selector(performTextFinderAction:) forKeyEquivalent:@"⌘E" tag:NSTextFinderActionSetSearchString];
    [m addAction:@selector(centerSelectionInVisibleArea:) forKeyEquivalent:@"⌘J" tag:0];
    [m addAction:@selector(showGuessPanel:) forKeyEquivalent:@"⇧⌘;" tag:0];
    [m addAction:@selector(checkSpelling:) forKeyEquivalent:@"⌘;" tag:0];
    [m addAction:@selector(orderFrontFontPanel:) forKeyEquivalent:@"⌘T" tag:0];
    [m addAction:@selector(addFontTrait:) forKeyEquivalent:@"⌘B" tag:NSBoldFontMask];
    [m addAction:@selector(addFontTrait:) forKeyEquivalent:@"⌘I" tag:NSItalicFontMask];
    [m addAction:@selector(underline:) forKeyEquivalent:@"⌘U" tag:0];
    [m addAction:@selector(modifyFont:) forKeyEquivalent:@"⌘=" tag:NSSizeUpFontAction];
    [m addAction:@selector(modifyFont:) forKeyEquivalent:@"⇧⌘=" tag:NSSizeUpFontAction];
    [m addAction:@selector(modifyFont:) forKeyEquivalent:@"⌘-" tag:NSSizeDownFontAction];
    [m addAction:@selector(modifyFont:) forKeyEquivalent:@"⇧⌘-" tag:NSSizeDownFontAction];
    [m addAction:@selector(orderFrontColorPanel:) forKeyEquivalent:@"⇧⌘C" tag:0];
    [m addAction:@selector(copyFont:) forKeyEquivalent:@"⌥⌘C" tag:0];
    [m addAction:@selector(pasteFont:) forKeyEquivalent:@"⌥⌘V" tag:0];
    [m addAction:@selector(alignLeft:) forKeyEquivalent:@"⇧⌘[" tag:0];
    [m addAction:@selector(alignCenter:) forKeyEquivalent:@"⇧⌘\\" tag:0];
    [m addAction:@selector(alignRight:) forKeyEquivalent:@"⇧⌘]" tag:0];
    [m addAction:@selector(copyRuler:) forKeyEquivalent:@"⌃⌘C" tag:0];
    [m addAction:@selector(pasteRuler:) forKeyEquivalent:@"⌃⌘V" tag:0];
    [m addAction:@selector(toggleToolbarShown:) forKeyEquivalent:@"⌥⌘T" tag:0];
    [m addAction:@selector(toggleSidebar:) forKeyEquivalent:@"⌃⌘S" tag:0];
    [m addAction:@selector(toggleFullScreen:) forKeyEquivalent:@"⌃⌘F" tag:0];
    [m addAction:@selector(performMiniaturize:) forKeyEquivalent:@"⌘M" tag:0];
    [m addAction:@selector(showHelp:) forKeyEquivalent:@"⇧⌘/" tag:0];
    return m;
}

+ (SRLocalShortcutMonitor *)clipboardShortcuts
{
    SRLocalShortcutMonitor *m = [SRLocalShortcutMonitor new];
    [m addAction:@selector(cut:) forKeyEquivalent:@"⌘X" tag:0];
    [m addAction:@selector(copy:) forKeyEquivalent:@"⌘C" tag:0];
    [m addAction:@selector(paste:) forKeyEquivalent:@"⌘V" tag:0];
    [m addAction:@selector(pasteAsPlainText:) forKeyEquivalent:@"⌥⇧⌘V" tag:0];
    [m addAction:@selector(undo:) forKeyEquivalent:@"⌘Z" tag:0];
    [m addAction:@selector(redo:) forKeyEquivalent:@"⇧⌘Z" tag:0];
    return m;
}

+ (SRLocalShortcutMonitor *)windowShortcuts
{
    SRLocalShortcutMonitor *m = [SRLocalShortcutMonitor new];
    [m addAction:@selector(performClose:) forKeyEquivalent:@"⌘W" tag:0];
    [m addAction:@selector(performMiniaturize:) forKeyEquivalent:@"⌘M" tag:0];
    [m addAction:@selector(toggleFullScreen:) forKeyEquivalent:@"⌃⌘F" tag:0];
    return m;
}

+ (SRLocalShortcutMonitor *)documentShortcuts
{
    SRLocalShortcutMonitor *m = [SRLocalShortcutMonitor new];
    [m addAction:@selector(print:) forKeyEquivalent:@"⌘P" tag:0];
    [m addAction:@selector(runPageLayout:) forKeyEquivalent:@"⇧⌘P" tag:0];
    [m addAction:@selector(revertDocumentToSaved:) forKeyEquivalent:@"⌘R" tag:0];
    [m addAction:@selector(saveDocument:) forKeyEquivalent:@"⌘S" tag:0];
    [m addAction:@selector(saveDocumentAs:) forKeyEquivalent:@"⇧⌥⌘S" tag:0];
    [m addAction:@selector(duplicateDocument:) forKeyEquivalent:@"⇧⌘S" tag:0];
    [m addAction:@selector(openDocument:) forKeyEquivalent:@"⌘O" tag:0];
    return m;
}

+ (SRLocalShortcutMonitor *)appShortcuts
{
    SRLocalShortcutMonitor *m = [SRLocalShortcutMonitor new];
    [m addAction:@selector(hide:) forKeyEquivalent:@"⌘H" tag:0];
    [m addAction:@selector(hideOtherApplications:) forKeyEquivalent:@"⌥⌘H" tag:0];
    [m addAction:@selector(terminate:) forKeyEquivalent:@"⌘Q" tag:0];
    return m;
}

#pragma mark Methods

- (BOOL)handleEvent:(NSEvent *)anEvent withTarget:(nullable id)aTarget
{
    SRShortcut *shortcut = [SRShortcut shortcutWithEvent:anEvent];
    if (!shortcut)
    {
        os_trace_error("#Error Not a keyboard event");
        return NO;
    }

    SRKeyEventType eventType = anEvent.SR_keyEventType;
    if (eventType == 0)
        return NO;

    __auto_type actions = [self enabledActionsForShortcut:shortcut keyEvent:eventType];
    __block BOOL isHandled = NO;
    [actions enumerateObjectsWithOptions:NSEnumerationReverse
                              usingBlock:^(SRShortcutAction *obj, NSUInteger idx, BOOL *stop)
    {
        *stop = isHandled = [obj performActionOnTarget:aTarget];
    }];

    return isHandled;
}

- (void)updateWithCocoaTextKeyBindings
{
    __auto_type systemKeyBindings = [self.class _parseSystemKeyBindings];
    __auto_type userKeyBindings = [self.class _parseUserKeyBindings];

    NSMutableDictionary *keyBindings = [systemKeyBindings mutableCopy];
    [keyBindings addEntriesFromDictionary:userKeyBindings];

    @synchronized (_actions)
    {
        [keyBindings enumerateKeysAndObjectsUsingBlock:^(NSString *aKey, id aValue, BOOL *aStop) {
            if (![aKey isKindOfClass:NSString.class] || !aKey.length)
                return;

            SRShortcut *shortcut = [SRShortcut shortcutWithKeyBinding:aKey];
            if (!shortcut)
                return;

            if (![aValue isKindOfClass:NSArray.class])
                aValue = @[aValue];

            for (NSString *keyBinding in (NSArray *)aValue)
            {
                if (![keyBinding isKindOfClass:NSString.class])
                    continue;
                else if (!keyBinding.length || [keyBinding isEqualToString:@"noop:"])
                {
                    // Only remove actions with static shortcuts.
                    __auto_type actions = [self->_shortcutToEnabledKeyDownActions objectForKey:shortcut];
                    NSIndexSet *actionsToRemove = [actions indexesOfObjectsPassingTest:^BOOL(SRShortcutAction *obj, NSUInteger idx, BOOL *stop) {
                        return obj.observedObject == nil;
                    }];
                    [actions removeObjectsAtIndexes:actionsToRemove];
                }
                else
                    [self addAction:[SRShortcutAction shortcutActionWithShortcut:shortcut target:nil action:NSSelectorFromString(aValue) tag:0]
                        forKeyEvent:SRKeyEventTypeDown];
            }
        }];
    }
}

#pragma mark Private

+ (NSDictionary<NSString *, id> *)_parseSystemKeyBindings
{
    NSBundle *appKitBundle = [NSBundle bundleWithIdentifier:@"com.apple.AppKit"];
    NSURL *systemKeyBindingsURL = [appKitBundle URLForResource:@"StandardKeyBinding" withExtension:@"dict"];
    NSDictionary *systemKeyBindings = nil;

    if (@available(macOS 10.13, *))
    {
        NSError *error = nil;
        systemKeyBindings = [NSDictionary dictionaryWithContentsOfURL:systemKeyBindingsURL error:&error];
        if (!systemKeyBindings)
        {
            os_trace_error_with_payload("#Error unable to read system key bindings", ^(xpc_object_t d) {
                xpc_dictionary_set_string(d, "error", error.localizedDescription.UTF8String);
            });
            systemKeyBindings = @{};
        }
    }
    else
    {
        systemKeyBindings = [NSDictionary dictionaryWithContentsOfURL:systemKeyBindingsURL];
        if (!systemKeyBindings)
        {
            os_trace_error("#Error unable to read system key bindings");
            systemKeyBindings = @{};
        }
    }

    return systemKeyBindings;
}

+ (NSDictionary<NSString *, id> *)_parseUserKeyBindings
{
    NSURL *userKeyBindingsURL = [NSURL fileURLWithPath:[@"~/Library/KeyBindings/DefaultKeyBinding.dict" stringByExpandingTildeInPath]];
    NSDictionary *userKeyBindings = nil;

    if (@available(macOS 10.13, *))
    {
        NSError *error = nil;
        userKeyBindings = [NSDictionary dictionaryWithContentsOfURL:userKeyBindingsURL error:&error];
        if (!userKeyBindings)
        {
            os_trace_debug_with_payload("#Error unable to read user key bindings", ^(xpc_object_t d) {
                xpc_dictionary_set_string(d, "error", error.localizedDescription.UTF8String);
            });
            userKeyBindings = @{};
        }
    }
    else
    {
        userKeyBindings = [NSDictionary dictionaryWithContentsOfURL:userKeyBindingsURL];
        if (!userKeyBindings)
        {
            os_trace_debug("#Error unable to read user key bindings");
            userKeyBindings = @{};
        }
    }

    return userKeyBindings;
}

@end
