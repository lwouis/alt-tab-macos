#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (void)catching:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
    } @catch (NSException *exception) {
        NSLog(@"Swallowed NSException: %@ — %@", exception.name, exception.reason);
    }
}

+ (BOOL)attempt:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

@end
