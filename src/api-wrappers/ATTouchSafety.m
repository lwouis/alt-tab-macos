@import Cocoa;
#import "ATTouchSafety.h"

@implementation ATTouchSafety

+ (BOOL)getNormalizedPosition:(NSTouch *)touch result:(NSPoint *)outPoint {
    @try {
        *outPoint = touch.normalizedPosition;
        return YES;
    } @catch (NSException *exception) {
        static BOOL logged = NO;
        if (!logged) {
            NSLog(@"ATTouchSafety: normalizedPosition threw %@: %@", exception.name, exception.reason);
            logged = YES;
        }
        return NO;
    }
}

@end
