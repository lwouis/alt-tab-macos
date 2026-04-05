//
//  Copyright 2018 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>

#import <ShortcutRecorder/SRRecorderControl.h>
#import <ShortcutRecorder/SRShortcut.h>
#import <ShortcutRecorder/SRShortcutAction.h>


NS_ASSUME_NONNULL_BEGIN

/*!
 Keys for the computed properties of controller's selection.
 */
typedef NSString *SRShortcutControllerSelectionKey NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(ShortcutControllerSelectionKey);
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyKeyEquivalent;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyKeyEquivalentModifierMask;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyLiteralKeyCode;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeySymbolicKeyCode;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyLiteralASCIIKeyCode;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeySymbolicASCIIKeyCode;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeyLiteralModifierFlags;
extern SRShortcutControllerSelectionKey const SRShortcutControllerSelectionKeySymbolicModifierFlags;


/*!
 Key paths for the computed properties of the controller.
 */
typedef NSString *SRShortcutControllerKeyPath NS_TYPED_EXTENSIBLE_ENUM NS_SWIFT_NAME(ShortcutControllerKeyPath);
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathKeyEquivalent;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathKeyEquivalentModifierMask;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathLiteralKeyCode;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathSymbolicKeyCode;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathLiteralASCIIKeyCode;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathSymbolicASCIIKeyCode;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathLiteralModifierFlags;
extern SRShortcutControllerKeyPath const SRShortcutControllerKeyPathSymbolicModifierFlags;

/*!
 Implementation of NSObjectController with additional computed properties.

 @discussion
 In addition to providing the common benefits of using NSObjectController over a plain model,
 it implements the following KVO-compliant computed properties:
 - selection.keyEquivalent
 - selection.keyEquivalentModifierMask
 - selection.literalKeyCode
 - selection.symbolicKeyCode
 - selection.literalASCIIKeyCode
 - selection.symbolicASCIIKeyCode
 - selection.literalModifierFlags
 - selection.symbolicModifierFlags

 Values of the following properties depend on the currently selected input source and
 also updated whenever kTISNotifySelectedKeyboardInputSourceChanged is posted:
 - selection.keyEquivalent
 - selection.literalKeyCode
 - selection.symbolicKeyCode
 - selection.literalASCIIKeyCode
 - selection.selection.symbolicASCIIKeyCode

 If the shortcutActionTarget property is set, the controller will automatically create and manage
 an instance of SRShortcutAction for that target.

 @note To add the controller in Interface Builder, add NSObjectController first and then specialize its class.
 */
NS_SWIFT_NAME(ShortcutController)
@interface SRShortcutController : NSObjectController <NSUserInterfaceItemIdentification>

/*!
 Target for the shortcutAction.

 @discussion
 If set, the controller will create an autoupdating instance of SRShortcutAction bound to Controller's content.

 @seealso SRShortcutActionTarget
 */
@property (nullable, weak) IBOutlet id<SRShortcutActionTarget> shortcutActionTarget;

/*!
 The shortcut action created by the controller.

 @note The instance is managed by the controller, do not modify it directly.
 */
@property (nullable, readonly) SRShortcutAction *shortcutAction;

/*!
 @seealso NSUserInterfaceItemIdentification
 */
@property (nullable, copy) IBInspectable NSString *identifier;

/*!
 Called by the designated initializers to set up internal state.
 */
- (void)initInternalState;

- (void)addSelectedKeyboardInputSourceObserverIfNeeded;
- (void)removeSelectedKeyboardInputSourceObserverIfNeeded;
- (void)onSelectedKeyboardInputSourceObserverChange;
- (void)updateComputedKeyPaths;

@end


@interface SRShortcutController (/* IBDesignable */)

/*!
 Recorder control to bind when loading from NIB.

 @discussion
 Controller will bind Control's NSValueBinding to the same source as its own NSContentObjectBinding
 by using the same transformers (usually NSKeyedUnarchiveFromData).
 As a result changes made via the Control will be propagated to the Model and therefore
 observed by the Controller and its own subscribers further down the chain.
*/
@property (weak) IBOutlet SRRecorderControl *recorderControl;

@end

NS_ASSUME_NONNULL_END
