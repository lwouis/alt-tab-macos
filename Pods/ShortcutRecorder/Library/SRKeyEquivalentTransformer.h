//
//  Copyright 2012 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Foundation/Foundation.h>
#import <ShortcutRecorder/SRShortcut.h>


NS_ASSUME_NONNULL_BEGIN

/*!
 Transform a shortcut or its dictionary representation into Cocoa's key equivalent
 for objects like NSButton and NSMenuItem.
 */
NS_SWIFT_NAME(KeyEquivalentTransformer)
@interface SRKeyEquivalentTransformer : NSValueTransformer

/*!
 Shared transformer.
 */
@property (class, readonly) SRKeyEquivalentTransformer *sharedTransformer NS_SWIFT_NAME(shared);

- (nullable NSString *)transformedValue:(nullable SRShortcut *)aValue;

@end

NS_ASSUME_NONNULL_END
