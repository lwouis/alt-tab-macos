@import Cocoa;

// NSTouch.normalizedPosition throws NSInternalInconsistencyException for touches
// delivered via Universal Control. Swift cannot catch NSException, so this ObjC
// wrapper provides a safe accessor that returns NO instead of crashing.
@interface ATTouchSafety : NSObject
+ (BOOL)getNormalizedPosition:(NSTouch *)touch result:(NSPoint *)outPoint;
@end
