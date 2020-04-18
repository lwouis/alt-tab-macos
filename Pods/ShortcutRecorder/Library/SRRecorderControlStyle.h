//
//  Copyright 2019 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <Foundation/Foundation.h>


@class SRRecorderControl;


NS_ASSUME_NONNULL_BEGIN

/*!
 @seealso SRRecorderControlStyleComponents/appearance
 */
typedef NS_ENUM(NSUInteger, SRRecorderControlStyleComponentsAppearance)
{
    SRRecorderControlStyleComponentsAppearanceUnspecified = 0,
    SRRecorderControlStyleComponentsAppearanceAqua,
    SRRecorderControlStyleComponentsAppearanceVibrantLight,
    SRRecorderControlStyleComponentsAppearanceDarkAqua,
    SRRecorderControlStyleComponentsAppearanceVibrantDark,

    SRRecorderControlStyleComponentsAppearanceMax NS_SWIFT_UNAVAILABLE("")
} NS_SWIFT_NAME(SRRecorderControlStyleComponents.Appearance);

/*!
 Return appearance from system's appearance.

 @discussion If system's appearance is not recognized unspecified is returned.

 @seealso NSAppearance/name
 */
SRRecorderControlStyleComponentsAppearance SRRecorderControlStyleComponentsAppearanceFromSystem(NSAppearanceName aSystemAppearanceName)
NS_SWIFT_NAME(SRRecorderControlStyleComponentsAppearance.init(fromSystem:));

/*!
 Return system's appearance name for SRRecorderControlStyleComponentsAppearance.

 @throws NSInvalidArgumentException If given value does not have system's counterpart.
 */
NSAppearanceName SRRecorderControlStyleComponentsAppearanceToSystem(SRRecorderControlStyleComponentsAppearance anAppearance)
NS_SWIFT_NAME(SRRecorderControlStyleComponentsAppearance(toSystem:));


/*!
 @seealso SRRecorderControlStyleComponents/tint
 */
typedef NS_ENUM(NSUInteger, SRRecorderControlStyleComponentsTint)
{
    SRRecorderControlStyleComponentsTintUnspecified = 0,
    SRRecorderControlStyleComponentsTintBlue,
    SRRecorderControlStyleComponentsTintGraphite,

    SRRecorderControlStyleComponentsTintMax NS_SWIFT_UNAVAILABLE("")
} NS_SWIFT_NAME(SRRecorderControlStyleComponents.Tint);


/*!
 Return tint for system's NSControlTint

 @discussion If system's tint is not recognized unspecified is returned.

 @seealso NSControlTint
 */
SRRecorderControlStyleComponentsTint SRRecorderControlStyleComponentsTintFromSystem(NSControlTint aSystemTint)
NS_SWIFT_NAME(SRRecorderControlStyleComponentsTint.init(fromSystem:));


/*!
 Return system's tint for SRRecorderControlStyleComponentsTint.

 @throws NSInvalidArgumentException If given value does not have system's counterpart.
 */
NSControlTint SRRecorderControlStyleComponentsTintToSystem(SRRecorderControlStyleComponentsTint aTint)
NS_SWIFT_NAME(SRRecorderControlStyleComponentsTint(toSystem:));


/*!
 @seealso SRRecorderControlStyleComponents/layoutDirection
 */
typedef NS_ENUM(NSUInteger, SRRecorderControlStyleComponentsLayoutDirection)
{
    SRRecorderControlStyleComponentsLayoutDirectionUnspecified = 0,
    SRRecorderControlStyleComponentsLayoutDirectionLeftToRight = 1,
    SRRecorderControlStyleComponentsLayoutDirectionRightToLeft = 2,

    SRRecorderControlStyleComponentsLayoutDirectionMax NS_SWIFT_UNAVAILABLE("")
} NS_SWIFT_NAME(SRRecorderControlStyleComponents.LayoutDirection);


/*!
 Return layout direction for system's NSUserInterfaceLayoutDirection

 @discussion If system's layout direction is not recognized unspecified is returned.

 @seealso NSUserInterfaceLayoutDirection
 */
SRRecorderControlStyleComponentsLayoutDirection SRRecorderControlStyleComponentsLayoutDirectionFromSystem(NSUserInterfaceLayoutDirection aSystemLayoutDirection)
NS_SWIFT_NAME(SRRecorderControlStyleComponentsLayoutDirection.init(fromSystem:));


/*!
 Return system's layout direction for SRRecorderControlStyleComponentsLayoutDirection.

 @throws NSInvalidArgumentException If given value does not have system's counterpart.
 */
NSUserInterfaceLayoutDirection SRRecorderControlStyleComponentsLayoutDirectionToSystem(SRRecorderControlStyleComponentsLayoutDirection aLayoutDirection)
NS_SWIFT_NAME(SRRecorderControlStyleComponentsLayoutDirection(toSystem:));


/*!
 @seealso SRRecorderControlStyleComponents/accessibility
 */
typedef NS_OPTIONS(NSUInteger, SRRecorderControlStyleComponentsAccessibility)
{
    SRRecorderControlStyleComponentsAccessibilityUnspecified NS_SWIFT_UNAVAILABLE("") = 0,
    SRRecorderControlStyleComponentsAccessibilityNone = 1 << 0,
    SRRecorderControlStyleComponentsAccessibilityHighContrast = 1 << 1,

    SRRecorderControlStyleComponentsAccessibilityMask NS_SWIFT_UNAVAILABLE("") = SRRecorderControlStyleComponentsAccessibilityNone | SRRecorderControlStyleComponentsAccessibilityHighContrast
} NS_SWIFT_NAME(SRRecorderControlStyleComponents.Accessibility);


/*!
 Recognized by SRRecorderControl to avoid label drawing if width of the target frame is smaller than the
 value of this attribute.
 */
extern NSAttributedStringKey const SRMinimalDrawableWidthAttributeName;


/*!
 Components of the style that describe visual appearance.

 The control may be in one of the following states:
    - Normal: the control is enabled but unpressed
    - Pressed: the control is enabled and pressed
    - Recording: the control is enabled and recording
    - Disabled: the control is disabled
 */
NS_SWIFT_NAME(RecorderControlStyle.Components)
@interface SRRecorderControlStyleComponents: NSObject <NSCopying>

/*!
 Current components based on the system settings.
 */
@property (class, nonatomic, readonly) SRRecorderControlStyleComponents *currentComponents NS_SWIFT_NAME(current);

@property (readonly) SRRecorderControlStyleComponentsAppearance appearance;
@property (readonly) SRRecorderControlStyleComponentsAccessibility accessibility;
@property (readonly) SRRecorderControlStyleComponentsLayoutDirection layoutDirection;
@property (readonly) SRRecorderControlStyleComponentsTint tint;

/*!
 Whether all components are specified.
 */
@property (getter=isSpecified, readonly) BOOL specified;

/*!
 String representation for the lookup prefixes.

 @discussion Format: [-{aqua, vibrantlight, vibrantdark, darkaqua}][-acc][-{ltr, rtl}][-{blue, graphite}]
 Fragments are optional and are not included if the corresponding value is either None or Unspecified.
 */
@property (readonly) NSString *stringRepresentation;

/*!
 Current components based on the system and view settings.

 @param aView Optional view whose settings are being considered.
 */
+ (SRRecorderControlStyleComponents *)currentComponentsForView:(nullable NSView *)aView NS_SWIFT_NAME(current(for:));

- (instancetype)initWithAppearance:(SRRecorderControlStyleComponentsAppearance)anAppearance
                     accessibility:(SRRecorderControlStyleComponentsAccessibility)anAccessibility
                   layoutDirection:(SRRecorderControlStyleComponentsLayoutDirection)aDirection
                              tint:(SRRecorderControlStyleComponentsTint)aTintNS_DESIGNATED_INITIALIZER;

- (BOOL)isEqualToComponents:(SRRecorderControlStyleComponents *)anObject;

/*!
 Compare components against the ideal.

 @discussion If the receiver is closer to the ideal, returns NSOrderedAscending.
 If anOtherComponents is closer, returns NSOrderedDescending.
 Otherwise, NSOrderedSame.
 */
- (NSComparisonResult)compare:(SRRecorderControlStyleComponents *)anOtherComponents
         relativeToComponents:(SRRecorderControlStyleComponents *)anIdealComponents;

@end


/*!
 Styling is responsible for providing resources and metrics to draw SRRecorderControl.
 */
NS_SWIFT_NAME(RecorderControlStyling)
@protocol SRRecorderControlStyling <NSCopying>

/*!
 Unique identifier of the style.
 */
@property (readonly) NSString *identifier;

/*!
 @seealso NSView/allowsVibrancy
 */
@property (readonly) BOOL allowsVibrancy;

/*!
 @seealso NSView/opaque
 */
@property (getter=isOpaque, readonly) BOOL opaque;

/*!
 Whether area under the label drawing frame is opaque.

 @discussion
 AppKit disables LCD smoothing for non-opaque layer-backed views. Styles that guarantee that area under
 the label is opaque want to enable LCD smoothing.

 @note Target context may still elect to disallow LCD smoothing

 @see CGContextSetShouldSmoothFonts
 @see CGContextSetAllowsFontSmoothing
 */
@property (getter=isLabelDrawingFrameOpaque, readonly) BOOL labelDrawingFrameOpaque;

/*!
 Unlike baselineLayoutOffsetFromBottom this is the true baseline where label is actually drawn.

 @seealso baselineLayoutOffsetFromBottom
 */
@property (readonly) CGFloat baselineDrawingOffsetFromBottom;

/*!
 @seealso NSView/alignmentRectInsets
 */
@property (readonly) NSEdgeInsets alignmentRectInsets;

/*!
 @seealso NSView/intrinsicContentSize
 */
@property (readonly) NSSize intrinsicContentSize;

/*!
 The guide that applies alignment insets to view's bounds.
 */
@property (readonly) NSLayoutGuide *alignmentGuide;

/*!
 The guide to draw view's label.
 */
@property (readonly) NSLayoutGuide *labelDrawingGuide;

/*!
 Constraints that should be always active.
 */
@property (readonly) NSArray<NSLayoutConstraint *> *alwaysConstraints;

/*!
 Constraints for not recording states.
 */
@property (readonly) NSArray<NSLayoutConstraint *> *displayingConstraints;

/*!
 Constraints for the recording state when there is no value and clear button should not be displayed.
 */
@property (readonly) NSArray<NSLayoutConstraint *> *recordingWithNoValueConstraints;

/*!
 Constraints for the recording state when there is a value and clear button should be displayed.
 */
@property (readonly) NSArray<NSLayoutConstraint *> *recordingWithValueConstraints;

@optional

/*!
 Default visual appearance components for the control.

 @discussion
 Style may provide custom values for the control properties such as userInterfaceLayoutDirection and appearance.
 Use the unspecified value to tell the control to use its own defaults.
 */
@property (readonly) SRRecorderControlStyleComponents *preferredComponents;

/*!
 Label attributes for displaying when enabled.
 */
@property (readonly) NSDictionary<NSAttributedStringKey, id> *normalLabelAttributes;

/*!
 Label attributes for displaying when recoding.
 */
@property (readonly) NSDictionary<NSAttributedStringKey, id> *recordingLabelAttributes;

/*!
 Label attributes for displaying when disabled.
 */
@property (readonly) NSDictionary<NSAttributedStringKey, id> *disabledLabelAttributes;

@property (readonly) NSImage *bezelNormalLeft;
@property (readonly) NSImage *bezelNormalCenter;
@property (readonly) NSImage *bezelNormalRight;

@property (readonly) NSImage *bezelPressedLeft;
@property (readonly) NSImage *bezelPressedCenter;
@property (readonly) NSImage *bezelPressedRight;

@property (readonly) NSImage *bezelRecordingLeft;
@property (readonly) NSImage *bezelRecordingCenter;
@property (readonly) NSImage *bezelRecordingRight;

@property (readonly) NSImage *bezelDisabledLeft;
@property (readonly) NSImage *bezelDisabledCenter;
@property (readonly) NSImage *bezelDisabledRight;

@property (readonly) NSImage *cancelButton;
@property (readonly) NSImage *cancelButtonPressed;

@property (readonly) NSImage *clearButton;
@property (readonly) NSImage *clearButtonPressed;

@property (readonly) NSString *noValueNormalLabel;
@property (readonly) NSString *noValueDisableLabel;
@property (readonly) NSString *noValueRecordingLabel;

@property (readonly) NSString *normalTooltip;
@property (readonly) NSString *disabledTooltip;
@property (readonly) NSString *recordingTooltip;
@property (readonly) NSString *cancelButtonTooltip;
@property (readonly) NSString *clearButtonTooltip;

/*!
 Corner radius of the focus ring.

 @discussion
 If not implemented, defaults to NSZeroSize.
 */
@property (readonly) NSSize focusRingCornerRadius;

/*!
 Insets of the focus ring relative to the alignment frame.

 @discussion
 If not implemented, defaults to NSEdgeInsetsZero.
 */
@property (readonly) NSEdgeInsets focusRingInsets;

/*!
 Baseline offset for autolayout alignment.

 @discussion
 If not implemented, defaults to baselineDrawingOffsetFromBottom.

 @seealso NSView/baselineOffsetFromBottom
 @seealso baselineDrawingOffsetFromBottom
 */
@property (readonly) CGFloat baselineLayoutOffsetFromBottom;

/*!
 The guide to draw view's background.

 @discussion
 If not implemented, defaults to control's bounds.
 */
@property (readonly) NSLayoutGuide *backgroundDrawingGuide;

/*!
 The guide to draw the cancel button.

 Is valid only when either recordingWithNoValueConstraints or recordingWithValueConstraints are active.

 @discussion
 If not implemented, defaults to zero rect.

 @seealso recordingWithNoValueConstraints
 @seealso recordingWithValueConstraints
 */
@property (readonly) NSLayoutGuide *cancelButtonDrawingGuide;

/*!
 The guide to draw the clear button.

 Is valid only when recordingWithValueConstraints are active.

 @discussion
 If not implemented, defaults to zero rect.

 @seealso recordingWithValueConstraints
 */
@property (readonly) NSLayoutGuide *clearButtonDrawingGuide;

/*!
 The guide for the clickable area of the cancel button.

 Is valid only when either recordingWithNoValueConstraints or recordingWithValueConstraints are active.

 @discussion
 If not implemented, defaults to cancelButtonDrawingGuide.

 @seealso recordingWithNoValueConstraints
 @seealso recordingWithValueConstraints
 */
@property (readonly) NSLayoutGuide *cancelButtonLayoutGuide;

/*!
 The guide for the clickable area of the clear button.

 Is valid only when recordingWithValueConstraints are active.

 @discussion
 If not implemented, defaults to clearButtonDrawingGuide.

 @seealso recordingWithValueConstraints
 */
@property (readonly) NSLayoutGuide *clearButtonLayoutGuide;

/*!
 Called just before style is applied to the specified control.

 @discussion
 Use this method to locate and cache resources, set up observers and install constraints.
 */
- (void)prepareForRecorderControl:(SRRecorderControl *)aControl NS_SWIFT_NAME(prepareForRecorderControl(_:));

/*!
 Called just before style is removed from the control it was added to.

 @discussion
 Use this method to free allocated resources, remove observers and remove constraints.
 */
- (void)prepareForRemoval;

/*!
 Called when view's appearance settings are changed.

 @seealso NSView/viewDidChangeBackingProperties
 @seealso NSControlTintDidChangeNotification
 @seealso NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification
 @seealso NSView/viewDidChangeEffectiveAppearance
 @seealso NSView/userInterfaceLayoutDirection
 */
- (void)recorderControlAppearanceDidChange:(nullable id)aReason;

@end


@class SRRecorderControlStyle;


/*!
 Locate and cache style resources.
 */
NS_SWIFT_NAME(SRRecorderControlStyle.ResourceLoader)
@interface SRRecorderControlStyleResourceLoader : NSObject

/*!
 Load info for the style.
 */
- (NSDictionary<NSString *, id> *)infoForStyle:(SRRecorderControlStyle *)aStyle;

/*!
 Make new lookup prefixes, ordered by best match to style's effective components.

 @seealso RecorderControlStyle/effectiveComponents
 */
- (NSArray<NSString *> *)lookupPrefixesForStyle:(SRRecorderControlStyle *)aStyle;

/*!
 Load image with a given name with respect to effective components.
 */
- (NSImage *)imageNamed:(NSString *)aName forStyle:(SRRecorderControlStyle *)aStyle;

@end


/*!
 Load style from resources.

 @discussion
 Searches for resources in:
    1. ShortcutRecorder Framework
    2. Main application bundle

 Resources are resolved according to the notion of style components represented
 by SRRecorderControlStyleComponents. Each such object defines envionment settings
 that may alter visual appearance, e.g. appearance and layout direction.
 Style automatically resolves current (or effective) components and orders available
 resources accordingly selecting the best match. If automatic resolution is not desirable
 specific set of components (or preffered) can be set during initialization.

 @seealso SRRecorderControlStyleResourceLoader
 @seealso SRRecorderControlStyleComponents
 */
NS_SWIFT_NAME(RecorderControlStyle)
@interface SRRecorderControlStyle : NSObject <SRRecorderControlStyling>

@property (class, readonly) SRRecorderControlStyleResourceLoader *resourceLoader;

@property (nullable, weak, readonly) SRRecorderControl *recorderControl;

/*!
 Currently effective components used to order lookup prefixes.

 @discussion Neither component has the unspecified value.
 */
@property (readonly) SRRecorderControlStyleComponents *effectiveComponents;

/*!
 Style that uses a given identifier to locate resources in the framework and application bundles.

 @param anIdentifier Identifier to locate the style.
                     Defaults to the best available for the system in framework's bundle.

 @param aComponents Custom components that override current system settings. The unspecified value can be
                    set for an individual component to allow a fallthrough.
                    Defaults all componenents to unspecified to allow complete fallthrough.

 @seealso effectiveComponents
 */
- (instancetype)initWithIdentifier:(nullable NSString *)anIdentifier
                        components:(nullable SRRecorderControlStyleComponents *)aComponents NS_DESIGNATED_INITIALIZER;

/*!
 Add style's constraints to the control view.
 */
- (void)addConstraints;

@end

NS_ASSUME_NONNULL_END
