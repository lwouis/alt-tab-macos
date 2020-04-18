//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Foundation/Foundation.h>
#import <ShortcutRecorder/SRShortcut.h>


NS_ASSUME_NONNULL_BEGIN

/*!
 Transform Cocoa Text system key binding into a shortcut.

 @seealso https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html
 */
NS_SWIFT_NAME(KeyBindingTransformer)
@interface SRKeyBindingTransformer : NSValueTransformer

/*!
 Shared transformer.
 */
@property (class, readonly) SRKeyBindingTransformer *sharedTransformer NS_SWIFT_NAME(shared);

- (nullable SRShortcut *)transformedValue:(nullable NSString *)aValue;
- (nullable NSString *)reverseTransformedValue:(nullable SRShortcut *)aValue;

@end

NS_ASSUME_NONNULL_END
