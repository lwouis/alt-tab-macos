// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MSACCustomDelegate;

/**
 * Enum used to represent all kind of executors running a completion handler.
 */
typedef NS_OPTIONS(NSUInteger, MSACCompletionExecutor) {
  MSACCompletionExecutorNone = (1 << 0),
  MSACCompletionExecutorOriginal = (1 << 1),
  MSACCompletionExecutorCustom = (1 << 2),
  MSACCompletionExecutorForwarder = (1 << 3)
};

@interface MSACDelegateForwarder : NSObject

/**
 * Enable/Disable Application forwarding.
 */
@property(atomic, getter=isEnabled) BOOL enabled;

/**
 * Hash table containing all the delegates as weak references.
 */
@property(nonatomic) NSHashTable<id<MSACCustomDelegate>> *delegates;

/**
 * Hold the original setDelegate implementation.
 */
@property(nonatomic) IMP originalSetDelegateImp;

// TODO SEL can be stored as NSValue in dictionaries for a better efficiency.
/**
 * Keep track of the original delegate's method implementations.
 */
@property(nonatomic, readonly) NSMutableDictionary<NSString *, NSValue *> *originalImplementations;

/**
 * Dictionary of deprecated original selectors indexed by their new equivalent.
 */
@property(nonatomic) NSDictionary<NSString *, NSString *> *deprecatedSelectors;

/**
 * Return the singleton instance of a delegate forwarder.
 *
 * @return The delegate forwarder instance.
 *
 * @discussion This method is abstract and needs to be overwritten by subclasses.
 */
+ (nullable instancetype)sharedInstance;

/**
 * Register swizzling for the given original application delegate.
 *
 * @param originalDelegate The original application delegate.
 */
- (void)swizzleOriginalDelegate:(NSObject *)originalDelegate;

/**
 * Add a delegate. This method is thread safe.
 *
 * @param delegate A delegate.
 */
- (void)addDelegate:(id<MSACCustomDelegate>)delegate;

/**
 * Remove a delegate. This method is thread safe.
 *
 * @param delegate A delegate.
 */
- (void)removeDelegate:(id<MSACCustomDelegate>)delegate;

/**
 * Add an app delegate selector to swizzle.
 *
 * @param selector An app delegate selector to swizzle.
 *
 * @discussion Due to the early registration of swizzling on the original app delegate each custom delegate must sign up for selectors to
 * swizzle within the @c load method of a category over the @see MSACAppDelegateForwarder class.
 */
- (void)addDelegateSelectorToSwizzle:(SEL)selector;

/**
 * Flush debugging traces accumulated until now.
 */
+ (void)flushTraceBuffer;

/**
 * Set the enabled state from the application plist file.
 *
 * @param plistKey Plist key for the forwarder enabled state.
 */
- (void)setEnabledFromPlistForKey:(NSString *)plistKey;

@end

NS_ASSUME_NONNULL_END
