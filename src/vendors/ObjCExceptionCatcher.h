@import Foundation;

@interface ObjCExceptionCatcher : NSObject
+ (void)catching:(NS_NOESCAPE void (^)(void))block;
// Like `catching:` but silent: returns NO if `block` threw instead of logging. Use on hot paths where a
// throw is expected and frequent (e.g. NSTouch.normalizedPosition for Universal Control touches, read
// per-touch per-event), so the caller falls back quietly rather than flooding the log.
+ (BOOL)attempt:(NS_NOESCAPE void (^)(void))block;
@end
