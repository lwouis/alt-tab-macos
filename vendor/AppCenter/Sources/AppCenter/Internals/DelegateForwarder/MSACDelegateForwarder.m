// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <objc/runtime.h>

#import "MSACAppCenterInternal.h"
#import "MSACCustomDelegate.h"
#import "MSACDelegateForwarder.h"
#import "MSACDelegateForwarderPrivate.h"
#import "MSACLogger.h"

static NSString *const kMSACCustomSelectorPrefix = @"custom_";
static NSString *const kMSACReturnedValueSelectorPart = @"returnedValue:";

// A buffer containing all the console logs that couldn't be printed yet.
static NSMutableArray<dispatch_block_t> *traceBuffer = nil;

@implementation MSACDelegateForwarder

@synthesize enabled = _enabled;

+ (void)load {
  traceBuffer = [NSMutableArray new];
}

- (instancetype)init {
  if ((self = [super init])) {
    _delegates = [NSHashTable weakObjectsHashTable];
    _selectorsToSwizzle = [NSMutableSet new];
    _originalImplementations = [NSMutableDictionary new];
    _enabled = YES;
  }
  return self;
}

+ (instancetype)sharedInstance {

  // This is an empty method expected to be overridden in sub classes.
  return nil;
}

+ (void)resetSharedInstance {

  // This is an empty method expected to be overridden in sub classes.
}

+ (NSString *)enabledKey {

  // This is an empty method expected to be overridden in sub classes.
  return nil;
}

- (Class)originalClassForSetDelegate {

  // This is an empty method expected to be overridden in sub classes.
  return nil;
}

- (dispatch_once_t *)swizzlingOnceToken {

  // This is an empty method expected to be overridden in sub classes.
  return nil;
}

#pragma mark - Custom Application

/**
 * Custom implementation of the setDelegate: method.
 *
 * @param delegate The delegate to be swizzled, its type here is @c id<NSObject> to be generic but your implementation will have to declare
 * the exact type of the expected delegate (i.e.: @c MSACApplicationDelegate).
 *
 * @discussion Beware, @c self in this method is not the current class but the swizzled class.
 */
- (void)custom_setDelegate:(__unused id<NSObject>)delegate {

  // This is an empty method expected to be overridden in sub classes.
}

#pragma mark - Logging

- (void)addTraceBlock:(void (^)(void))block {
  @synchronized(traceBuffer) {
    if (traceBuffer) {
      static dispatch_once_t onceToken = 0;
      dispatch_once(&onceToken, ^{
        [traceBuffer addObject:^{
          MSACLogVerbose([MSACAppCenter logTag], @"Start buffering traces.");
        }];
      });
      [traceBuffer addObject:block];
    } else {
      block();
    }
  }
}

+ (void)flushTraceBuffer {
  if (traceBuffer) {
    @synchronized(traceBuffer) {
      for (dispatch_block_t traceBlock in traceBuffer) {
        traceBlock();
      }
      [traceBuffer removeAllObjects];
      traceBuffer = nil;
      MSACLogVerbose([MSACAppCenter logTag], @"Stop buffering traces, flushed.");
    }
  }
}

#pragma mark - Swizzling

- (void)addDelegateSelectorToSwizzle:(SEL)selector {
  if (self.enabled) {

    // Swizzle only once and only if needed. No selector to swizzle then no swizzling at all.
    dispatch_once([self swizzlingOnceToken], ^{
      self.originalSetDelegateImp = [self swizzleOriginalSelector:@selector(setDelegate:)
                                               withCustomSelector:@selector(custom_setDelegate:)
                                                    originalClass:[self originalClassForSetDelegate]];
    });
    [self.selectorsToSwizzle addObject:NSStringFromSelector(selector)];
  }
}

- (void)swizzleOriginalDelegate:(NSObject *)originalDelegate {
  IMP originalImp = NULL;
  Class delegateClass = [originalDelegate class];
  SEL originalSelector, customSelector;

  // Swizzle all registered selectors.
  for (NSString *selectorString in self.selectorsToSwizzle) {
    originalSelector = NSSelectorFromString(selectorString);
    customSelector = NSSelectorFromString([kMSACCustomSelectorPrefix stringByAppendingString:selectorString]);
    originalImp = [self swizzleOriginalSelector:originalSelector withCustomSelector:customSelector originalClass:delegateClass];
    if (originalImp) {

      // Save the original implementation for later use.
      self.originalImplementations[selectorString] = [NSValue valueWithBytes:&originalImp objCType:@encode(IMP)];
    }
  }
  [self.selectorsToSwizzle removeAllObjects];
}

- (IMP)swizzleOriginalSelector:(SEL)originalSelector withCustomSelector:(SEL)customSelector originalClass:(Class)originalClass {

  // Replace original implementation
  NSString *originalSelectorStr = NSStringFromSelector(originalSelector);
  Method originalMethod = class_getInstanceMethod(originalClass, originalSelector);
  IMP customImp = class_getMethodImplementation([self class], customSelector);
  IMP originalImp = NULL;
  BOOL methodAdded = NO;
  BOOL skipped = NO;
  NSString *warningMsg;
  NSString *remediationMsg = @"You need to explicitly call the App Center API from your app delegate implementation.";

  // Replace original implementation by the custom one.
  if (originalMethod) {
    originalImp = method_setImplementation(originalMethod, customImp);
  } else if (![originalClass instancesRespondToSelector:originalSelector]) {

    // Check for deprecation.
    NSString *deprecatedSelectorStr = self.deprecatedSelectors[originalSelectorStr];
    if (deprecatedSelectorStr && [originalClass instancesRespondToSelector:NSSelectorFromString(deprecatedSelectorStr)]) {

      // An implementation for the deprecated selector exists. Don't add the new method, it might eclipse the original implementation.
      warningMsg = [NSString
          stringWithFormat:@"No implementation found for this selector, though an implementation of its deprecated API '%@' exists.",
                           deprecatedSelectorStr];
    } else {

      // Skip this selector if it's deprecated and doesn't have an implementation.
      if ([self.deprecatedSelectors.allValues containsObject:originalSelectorStr]) {
        skipped = YES;
      } else {

        /*
         * The original class may not implement the selector (e.g.: optional method from protocol), add the method to the original class and
         * associate it with the custom implementation.
         */
        Method customMethod = class_getInstanceMethod([self class], customSelector);
        methodAdded = class_addMethod(originalClass, originalSelector, customImp, method_getTypeEncoding(customMethod));
      }
    }
  }

  /*
   * If class instances respond to the selector but no implementation is found it's likely that the original class is doing message
   * forwarding, in this case we can't add our implementation to the class or we will break the forwarding.
   */

  // Validate swizzling.
  if (!skipped) {
    if (!originalImp && !methodAdded) {
      [self addTraceBlock:^{
        NSString *message = [NSString stringWithFormat:@"Cannot swizzle selector '%@' of class '%@'.", originalSelectorStr, originalClass];
        if (warningMsg) {
          MSACLogWarning([MSACAppCenter logTag], @"%@ %@", message, warningMsg);
        } else {
          MSACLogError([MSACAppCenter logTag], @"%@ %@", message, remediationMsg);
        }
      }];
    } else {
      [self addTraceBlock:^{
        MSACLogDebug([MSACAppCenter logTag], @"Selector '%@' of class '%@' is swizzled.", originalSelectorStr, originalClass);
      }];
    }
  }
  return originalImp;
}

#pragma mark - Forwarding

- (void)forwardInvocation:(NSInvocation *)invocation {
  @synchronized([self class]) {
    BOOL forwarded = NO;
    BOOL hasReturnedValue = ([NSStringFromSelector(invocation.selector) hasSuffix:kMSACReturnedValueSelectorPart]);
    NSUInteger returnedValueIdx = 0;
    void *returnedValuePtr = NULL;

    // Prepare returned value if any.
    if (hasReturnedValue) {

      // Returned value argument is always the last one.
      returnedValueIdx = invocation.methodSignature.numberOfArguments - 1;
      returnedValuePtr = malloc(invocation.methodSignature.methodReturnLength);
    }

    // Forward to delegates executing a custom method.
    for (id<MSACCustomDelegate> delegate in self.delegates) {
      if ([delegate respondsToSelector:invocation.selector]) {
        [invocation invokeWithTarget:delegate];

        // Chaining return values.
        if (hasReturnedValue) {
          [invocation getReturnValue:returnedValuePtr];
          [invocation setArgument:returnedValuePtr atIndex:returnedValueIdx];
        }
        forwarded = YES;
      }
    }

    // Forward back the original return value if no delegates to receive the message.
    if (hasReturnedValue && !forwarded) {
      [invocation getArgument:returnedValuePtr atIndex:returnedValueIdx];
      [invocation setReturnValue:returnedValuePtr];
    }
    free(returnedValuePtr);
  }
}

#pragma mark - Delegates

- (void)addDelegate:(id<MSACCustomDelegate>)delegate {
  @synchronized(self) {
    if (self.enabled) {
      [self.delegates addObject:delegate];
    }
  }
}

- (void)removeDelegate:(id<MSACCustomDelegate>)delegate {
  @synchronized(self) {
    if (self.enabled) {
      [self.delegates removeObject:delegate];
    }
  }
}

#pragma mark - Other

- (void)setEnabledFromPlistForKey:(NSString *)plistKey {
  NSNumber *forwarderEnabledNum = [NSBundle.mainBundle objectForInfoDictionaryKey:plistKey];
  BOOL forwarderEnabled = forwarderEnabledNum ? [forwarderEnabledNum boolValue] : YES;
  self.enabled = forwarderEnabled;
  if (self.enabled) {
    [self addTraceBlock:^{
      MSACLogDebug([MSACAppCenter logTag], @"Delegate forwarder for info.plist key '%@' enabled. It may use swizzling.", plistKey);
    }];
  } else {
    [self addTraceBlock:^{
      MSACLogDebug([MSACAppCenter logTag], @"Delegate forwarder for info.plist key '%@' disabled. It won't use swizzling.", plistKey);
    }];
  }
}

- (BOOL)isEnabled {
  return _enabled;
}

- (void)setEnabled:(BOOL)enabled {
  @synchronized(self) {
    _enabled = enabled;
    if (!enabled) {
      [self.delegates removeAllObjects];
    }
  }
}

@end
