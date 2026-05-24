@import Foundation;

@interface ObjCExceptionCatcher : NSObject
+ (void)catching:(NS_NOESCAPE void (^)(void))block;
@end
