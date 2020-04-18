//
//  Copyright 2012 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN

@class SRLiteralModifierFlagsTransformer;

/*!
 Don't use directly. Use SRLiteralModifierFlagsTransformer / SRSymbolicModifierFlagsTransformer instead.
 */
NS_SWIFT_UNAVAILABLE("use SRLiteralModifierFlagsTransformer / SRSymbolicModifierFlagsTransformer instead")
@interface SRModifierFlagsTransformer : NSValueTransformer
/*!
 Shared transformer.
 */
@property (class, readonly) SRModifierFlagsTransformer* sharedTransformer NS_SWIFT_NAME(shared);

/*!
 Order modifier flags according to the user interface layout direction of the view.

 @param aDirection The layout direction to select an appropriate symbol or literal.
 */
- (nullable NSString *)transformedValue:(NSNumber *)aValue layoutDirection:(NSUserInterfaceLayoutDirection)aDirection;

- (nullable NSString *)transformedValue:(nullable NSNumber *)aValue;

@end


@interface SRModifierFlagsTransformer (Deprecated)
+ (SRLiteralModifierFlagsTransformer *)sharedPlainTransformer __attribute__((deprecated("", "SRLiteralModifierFlagsTransformer.shared")));
- (instancetype)initWithPlainStrings:(BOOL)aUsesPlainStrings __attribute__((deprecated));
@property (readonly) BOOL usesPlainStrings __attribute__((deprecated));
@end


/*!
 Transform modifier flags into a univesal symbolic string such as ⌘⌥.

 @note Allows reverse transformation.
 */
NS_SWIFT_NAME(LiteralModifierFlagsTransformer)
@interface SRLiteralModifierFlagsTransformer: SRModifierFlagsTransformer
@end


/*!
 Transform modifier flags into a localized literal string such as Command-Option.
 */
NS_SWIFT_NAME(SymbolicModifierFlagsTransformer)
@interface SRSymbolicModifierFlagsTransformer: SRModifierFlagsTransformer
@end

NS_ASSUME_NONNULL_END
