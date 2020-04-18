//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>

#import <ShortcutRecorder/SRShortcut.h>


/*!
 @header
 A collection of classes to bind shortcuts to actions and monitor these actions in
 event streams.
 */


NS_ASSUME_NONNULL_BEGIN

@class SRShortcutAction;

/*!
 @param anAction The action that invoked the handler.

 @return YES if the action was performed; NO otherwise.
 */
typedef BOOL (^SRShortcutActionHandler)(SRShortcutAction *anAction) NS_SWIFT_NAME(SRShortcutAction.Action);


NS_SWIFT_NAME(ShortcutActionTarget)
@protocol SRShortcutActionTarget;


/*!
 A connection between a shortcut and an action.

 @discussion
 The associated shortcut can be set directly or it can be observed from another object. In the latter case
 whenever new value is observed, the shortcut property is updated in a KVO-complient way.

 The associated action can be a selector or a block.
 A target for the selector can be stored inside the action, but can also be provided directly
 to the -performActionOnTarget: method. This is convenient when the target is not known
 at the time when the action is created.

 The target may adapt the SRShortcutActionTarget protocol instead of implementing a method for each action.
 Additionaly, the NSUserInterfaceValidations protocol can be adapted to determine whether the action should be ignored.

 Both selector and block implementations must return a boolean determining whether the action
 was actually performed. This helps the monitor to find the suitable action when there are multiple
 actions per a shortcut.
 */
NS_SWIFT_NAME(ShortcutAction)
@interface SRShortcutAction : NSObject <NSValidatedUserInterfaceItem, NSUserInterfaceItemIdentification>

/*!
 Instantiate a selector-based action bound to the shortcut.
 */
+ (instancetype)shortcutActionWithShortcut:(SRShortcut *)aShortcut
                                    target:(nullable id)aTarget
                                    action:(nullable SEL)anAction
                                       tag:(NSInteger)aTag;

/*!
 Instantiate a block-based action bound to the shortcut.
 */
+ (instancetype)shortcutActionWithShortcut:(SRShortcut *)aShortcut
                             actionHandler:(SRShortcutActionHandler)anActionHandler;

/*!
 Instantiate a selector-based action bound to the autoupdating shortcut.
 */
+ (instancetype)shortcutActionWithKeyPath:(NSString *)aKeyPath
                                 ofObject:(id)anObject
                                   target:(nullable id)aTarget
                                   action:(nullable SEL)anAction
                                      tag:(NSInteger)aTag;

/*!
 Instantiate a block-based action bound to the autoupdating shortcut.
 */
+ (instancetype)shortcutActionWithKeyPath:(NSString *)aKeyPath
                                 ofObject:(id)anObject
                            actionHandler:(SRShortcutActionHandler)anActionHandler;

/*!
 The shortcut associated with the action.

 @note Setting the shortcut resets observation.
 */
@property (nullable, copy) SRShortcut *shortcut;

/*!
 The object being observed for the autoupdating shortcut.
 */
@property (nullable, weak, readonly) id observedObject;

/*!
 The key path being observed for the autoupdating shortcut.
 */
@property (nullable, copy, readonly) NSString *observedKeyPath;

/*!
 The target to receive the associated action-message selector.

 @discussion
 Defaults to NSApplication.sharedApplication

 @note Setting the target resets the action handler.

 @seealso SRShortcutActionTarget
 */
@property (null_resettable, weak) id target;

/*!
 The selector associated with the action.

 @discussion
 May be nil if the target conforms to the SRShortcutActionTarget protocol.
 */
@property (nullable) SEL action;

/*!
 The handler to execute when the action is performed.

 @note Setting the handler resets the target.
 */
@property (nullable) SRShortcutActionHandler actionHandler;

/*!
 The tag identifying the receiver.
 */
@property NSInteger tag;

/*!
 Whether the action is enabled.
 */
@property (getter=isEnabled) BOOL enabled;

/*!
 Configure the autoupdating shortcut by observing the given key path of the given object.

 @discussion
 anObservedObject is expected to return one of:
 - SRShortcut
 - A compatible NSDictionary representation
 - NSData of encoded SRShortcut
 - nil / NSNull

 @note To stop observation set the shortcut to nil or any other value.
 */
- (void)setObservedObject:(id)anObservedObject withKeyPath:(NSString *)aKeyPath;

/*!
 Perform the associated action, if any, on the given target, if possible.

 @param aTarget Target to perform the associated action. If nil, defaults to action's target.

 @discussion
 Disabled actions return NO immediately.

 If there is an associated action handler, it is performed and aTarget is ignored.
 Otherwise, the associated action is performed if:
 1. aTarget either implements the action or adopts the SRShortcutActionTarget protocol
 2. aTarget's -validateUserInterfaceItem:, if implemented, returns YES

 @return YES if the action was performed; NO otherwise.
 */
- (BOOL)performActionOnTarget:(nullable id)aTarget;

@end


/*!
 A target of SRShortcutAction may adopt this protocol to receive a message without implementing distinct methods.
 The implementation may use anAction's tag and identifier properties to distinguish senders.

 @seealso NSValidatedUserInterfaceItem
 @seealso NSUserInterfaceItemIdentification
 */
@protocol SRShortcutActionTarget
- (BOOL)performShortcutAction:(SRShortcutAction *)anAction NS_SWIFT_NAME(perform(shortcutAction:));
@end


/*!
 Type of the keyboard event.

 @const SRKeyEventTypeUp Keyboard key is released.
 @const SRKeyEventTypeDown Keyboard key is pressed.
 */
typedef NS_CLOSED_ENUM(NSUInteger, SRKeyEventType)
{
    SRKeyEventTypeUp = NSEventTypeKeyUp,
    SRKeyEventTypeDown = NSEventTypeKeyDown
} NS_SWIFT_NAME(KeyEventType);


@interface NSEvent (SRShortcutAction)

/*!
 Keyboard event type as recognized by the shortcut recorder.
 */
@property (readonly) SRKeyEventType SR_keyEventType;

@end


/*!
 Base class for the SRGlobalShortcutMonitor and SRLocalShortcutMonitor.

 @discussion
 Observes shortcuts assigned to actions and automatically rearranges internal storage.

 The monitor supports multiple actions associated with the same shortcut. When that happens,
 the monitor attempts to perform the most recent action that claimed the shortcut. If it fails,
 it tries the next most recent one and so on until either the action is succesfully performed or the list
 of candidates is exhausted.

 There are two key events supported by the monitor: key down and key up.

 The same action (identical object) may be associated with multiple shortcuts as well as both key events for the same
 shortcut.

 The recency of actions is established first by the order of addition and then by the recency
 of the dynamic shortcut change (both direct and through observation).
 */
NS_SWIFT_NAME(ShortcutMonitor)
@interface SRShortcutMonitor : NSObject

/*!
 All shortcut actions.
 */
@property (copy, readonly) NSArray<SRShortcutAction *> *actions;

/*!
 All shortcuts being monitored.
 */
@property (copy, readonly) NSArray<SRShortcut *> *shortcuts;

/*!
 All actions for a given key event in no particular order.
 */
- (NSArray<SRShortcutAction *> *)actionsForKeyEvent:(SRKeyEventType)aKeyEvent NS_SWIFT_NAME(actions(forKeyEvent:));

/*!
 Enabled actions for a given shortcut and key event.

 @return
 Order is determined by the time of association such as that the last object is the most recently associated.
 If the shortcut has no associated actions, returns an empty array.
 */
- (NSArray<SRShortcutAction *> *)enabledActionsForShortcut:(SRShortcut *)aShortcut
                                                  keyEvent:(SRKeyEventType)aKeyEvent NS_SWIFT_NAME(enabledActions(forShortcut:keyEvent:));

/*!
 Add an action to the monitor for a key event.

 @discussion
 Adding the same action for the same event type again only changes its order by making it the most recent.
 */
- (void)addAction:(SRShortcutAction *)anAction forKeyEvent:(SRKeyEventType)aKeyEvent NS_SWIFT_NAME(addAction(_:forKeyEvent:));

/*!
 Remove an action, if present, from the monitor for a specific key event.
 */
- (void)removeAction:(SRShortcutAction *)anAction forKeyEvent:(SRKeyEventType)aKeyEvent NS_SWIFT_NAME(removeAction(_:forKeyEvent:));

/*!
 Remove an action, if present, from the monitor.
 */
- (void)removeAction:(SRShortcutAction *)anAction NS_SWIFT_NAME(removeAction(_:));

/*!
 Remove all actions from the monitor.
 */
- (void)removeAllActions;

/*!
 Called before the shortcut gets its first associated enabled action.

 @note Do not mutate actions within the callback.
 */
- (void)willAddShortcut:(SRShortcut *)aShortcut NS_SWIFT_NAME(willAddShortcut(_:));

/*!
 Called after the shortcut gets its first associated enabled action.

 @note Do not mutate actions within the callback.
 */
- (void)didAddShortcut:(SRShortcut *)aShortcut NS_SWIFT_NAME(didAddShortcut(_:));

/*!
 Called before the shortcuts loses its last associated enabled action.

 @note Do not mutate actions within the callback.
 */
- (void)willRemoveShortcut:(SRShortcut *)aShortcut NS_SWIFT_NAME(willRemoveShortcut(_:));

/*!
 Called after the shortcut loses its last associated enabled action.

 @note Do not mutate actions within the callback.
 */
- (void)didRemoveShortcut:(SRShortcut *)aShortcut NS_SWIFT_NAME(didRemoveShortcut(_:));

@end


@interface SRShortcutMonitor (SRShortcutMonitorConveniences)

/*!
 Create and add new action with given parameters.
 */
- (nullable SRShortcutAction *)addAction:(SEL)anAction forKeyEquivalent:(NSString *)aKeyEquivalent tag:(NSInteger)aTag;

@end


extern const OSType SRShortcutActionSignature;


/*!
 Handle shortcuts regardless of the currently active application via Carbon Hot Key API.

 @note Does not support shortcuts with the SRKeyCodeNone key code.

 @see SRAXGlobalShortcutMonitor
 */
NS_SWIFT_NAME(GlobalShortcutMonitor)
@interface SRGlobalShortcutMonitor : SRShortcutMonitor

@property (class, readonly) SRGlobalShortcutMonitor *sharedMonitor NS_SWIFT_NAME(shared);

/*!
 Enable system-wide shortcut monitoring.

 @discussion
 This method has an underlying counter, i.e. every pause must be matched with a resume.
 The initial state is resumed.
 */
- (void)resume;

/*!
 Disable system-wide shortcut monitoring.

 @discussion
 This method has an underlying counter, i.e. every pause must be matched with a resume.
 The initial state is resumed.
 */
- (void)pause;

/*!
 Perform the action associated with a given event.

 @param anEvent A Carbon hot key event.

 @return noErr if event is handeled; one of the Carbon errors otherwise.

 @discussion
 If there is more than one action associated with the event, they are performed one by one
 either until one of them returns YES or the iteration is exhausted.
 */
- (OSStatus)handleEvent:(EventRef)anEvent;

/*!
 Called after the carbon event handler is installed.
*/
- (void)didAddEventHandler;

/*!
 Called after the carbon event handler is removed.
*/
- (void)didRemoveEventHandler;

@end


/*!
 Handle shortcuts regardless of the currently active application via Quartz Event Service API.

 @discussion
 Unlike SRGlobalShortcutMonitor it can handle shortcuts with the SRKeyCodeNone key code. But it has
 security implications as this API requires the app to either run under the root user or been allowed
 the Accessibility permission.

 The monitor automatically enables and disables the tap when needed.

 @see SRGlobalShortcutMonitor
 @see AXIsProcessTrustedWithOptions
 @see NSAppleEventsUsageDescription
 */
@interface SRAXGlobalShortcutMonitor : SRShortcutMonitor

/*!
 Mach port that corresponds to the event tap used under the hood.
 */
@property (readonly) CFMachPortRef eventTap;
- (CFMachPortRef)eventTap NS_RETURNS_INNER_POINTER CF_RETURNS_NOT_RETAINED;

/*!
 Run loop source that corresponds to the eventTap.
 */
@property (readonly) CFRunLoopSourceRef eventTapSource;
- (CFRunLoopSourceRef)eventTapSource NS_RETURNS_INNER_POINTER CF_RETURNS_NOT_RETAINED;

/*!
 Run loop that corresponds to the eventTap.
 */
@property (readonly) NSRunLoop *eventTapRunLoop;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability"
/*!
 Initialize the monitor by installing the event tap in the current run loop.
 */
- (nullable instancetype)init;
#pragma clang diagnostic pop

/*!
 Initialize the monitor by installing the event tap in a given run loop.

 @param aRunLoop Run loop for the event tap.

 @discussion
 Initialization may fail if it's impossible to create the event tap.

 @see https://stackoverflow.com/q/52738506/188530
 */
- (nullable instancetype)initWithRunLoop:(NSRunLoop *)aRunLoop NS_DESIGNATED_INITIALIZER;

/*!
 Perform the action associated with a given event.

 @param anEvent A Quartz keyboard event.

 @return nil if event is handled; unchanged anEvent otherwise.

 @discussion
 If there is more than one action associated with the event, they are performed one by one
 either until one of them returns YES or the iteration is exhausted.
 */
- (nullable CGEventRef)handleEvent:(CGEventRef)anEvent;

@end


/*!
 Handle AppKit's keyboard events.

 @discussion
 The monitor does not intercept any events. Instead they must be passed directly. Override NSView/NSWindow
 or NSViewController/NSWindowController or use NSEvent's monitoring API to pass keyboard events
 via the -handleEvent:withTarget: method.
 */
NS_SWIFT_NAME(LocalShortcutMonitor)
@interface SRLocalShortcutMonitor : SRShortcutMonitor

/*!
 Text navigation and editing shortcuts.

 @seealso NSStandardKeyBindingResponding
 */
@property (class, readonly, copy) SRLocalShortcutMonitor *standardShortcuts;

/*!
 Shortcuts that mimic default main menu for a new Cocoa Applications.
 */
@property (class, readonly, copy) SRLocalShortcutMonitor *mainMenuShortcuts;

/*!
 Shortcuts associated with the clipboard.

 - cut:
 - copy:
 - paste:
 - pasteAsPlainText:
 - redo:
 - undo:
 */
@property (class, readonly, copy) SRLocalShortcutMonitor *clipboardShortcuts;

/*!
 Shortcuts associated with window management.

 - performClose:
 - performMiniaturize:
 - toggleFullScreen:
 */
@property (class, readonly, copy) SRLocalShortcutMonitor *windowShortcuts;

/*!
 Key bindings associated with document management.

 - print:
 - runPageLayout:
 - revertDocumentToSaved:
 - saveDocument:
 - saveDocumentAs:
 - duplicateDocument:
 - openDocument:
 */
@property (class, readonly, copy) SRLocalShortcutMonitor *documentShortcuts;

/*!
 Key bindings associated with application management.

 - hide:
 - hideOtherApplications:
 - terminate:
 */
@property (class, readonly, copy) SRLocalShortcutMonitor *appShortcuts;

/*!
 Perform the action associated with the event, if any.

 @param anEvent An AppKit keyboard event.

 @param aTarget Target to pass to the -[SRShortcutAction performActionOnTarget:] method.

 @discussion
 If there are more than one action associated with the event, they are performed one by one
 either until one of them returns YES or the iteration is exhausted.
 */
- (BOOL)handleEvent:(NSEvent *)anEvent withTarget:(nullable id)aTarget;

/*!
 Update the monitor with system-wide and user-specific Cocoa Text System key bindings.

 @seealso https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html
 */
- (void)updateWithCocoaTextKeyBindings;

@end

NS_ASSUME_NONNULL_END
