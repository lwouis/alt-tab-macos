//
//  Copyright 2006 ShortcutRecorder Contributors
//  CC BY 4.0
//

#import <objc/runtime.h>

#import "SRCommon.h"


// Xcode 27.1's x86_64 linker coalesces distinct UTF-16 literals after the package's `ld -r` step
// (#6138). Build the exported glyph strings from UTF-8 at load time so the default hold modifiers
// and key labels retain their values. `testModifierSymbolsKeepTheirFlags` pins the parsing contract.
SRKeyCodeString SRKeyCodeStringTabRight;
SRKeyCodeString SRKeyCodeStringTabLeft;
SRKeyCodeString SRKeyCodeStringReturn;
SRKeyCodeString SRKeyCodeStringReturnR2L;
SRKeyCodeString SRKeyCodeStringDeleteLeft;
SRKeyCodeString SRKeyCodeStringDeleteRight;
SRKeyCodeString SRKeyCodeStringPadClear;
SRKeyCodeString SRKeyCodeStringLeftArrow;
SRKeyCodeString SRKeyCodeStringRightArrow;
SRKeyCodeString SRKeyCodeStringUpArrow;
SRKeyCodeString SRKeyCodeStringDownArrow;
SRKeyCodeString SRKeyCodeStringPageDown;
SRKeyCodeString SRKeyCodeStringPageUp;
SRKeyCodeString SRKeyCodeStringNorthwestArrow;
SRKeyCodeString SRKeyCodeStringSoutheastArrow;
SRKeyCodeString SRKeyCodeStringEscape;
SRKeyCodeString const SRKeyCodeStringSpace = @" ";
SRKeyCodeString SRKeyCodeStringHelp;
SRKeyCodeString SRKeyCodeStringJISUnderscore;
SRKeyCodeString SRKeyCodeStringJISComma;
SRKeyCodeString SRKeyCodeStringJISYen;

SRModifierFlagString SRModifierFlagStringCommand;
SRModifierFlagString SRModifierFlagStringOption;
SRModifierFlagString SRModifierFlagStringShift;
SRModifierFlagString SRModifierFlagStringControl;

__attribute__((constructor)) static void SRMakeNonASCIIStrings(void)
{
    SRKeyCodeStringTabRight = [NSString stringWithUTF8String:"⇥"];
    SRKeyCodeStringTabLeft = [NSString stringWithUTF8String:"⇤"];
    SRKeyCodeStringReturn = [NSString stringWithUTF8String:"⌅"];
    SRKeyCodeStringReturnR2L = [NSString stringWithUTF8String:"↩"];
    SRKeyCodeStringDeleteLeft = [NSString stringWithUTF8String:"⌫"];
    SRKeyCodeStringDeleteRight = [NSString stringWithUTF8String:"⌦"];
    SRKeyCodeStringPadClear = [NSString stringWithUTF8String:"⌧"];
    SRKeyCodeStringLeftArrow = [NSString stringWithUTF8String:"←"];
    SRKeyCodeStringRightArrow = [NSString stringWithUTF8String:"→"];
    SRKeyCodeStringUpArrow = [NSString stringWithUTF8String:"↑"];
    SRKeyCodeStringDownArrow = [NSString stringWithUTF8String:"↓"];
    SRKeyCodeStringPageDown = [NSString stringWithUTF8String:"⇟"];
    SRKeyCodeStringPageUp = [NSString stringWithUTF8String:"⇞"];
    SRKeyCodeStringNorthwestArrow = [NSString stringWithUTF8String:"↖"];
    SRKeyCodeStringSoutheastArrow = [NSString stringWithUTF8String:"↘"];
    SRKeyCodeStringEscape = [NSString stringWithUTF8String:"⎋"];
    SRKeyCodeStringHelp = [NSString stringWithUTF8String:"?⃝"];
    SRKeyCodeStringJISUnderscore = [NSString stringWithUTF8String:"＿"];
    SRKeyCodeStringJISComma = [NSString stringWithUTF8String:"、"];
    SRKeyCodeStringJISYen = [NSString stringWithUTF8String:"¥"];
    SRModifierFlagStringCommand = [NSString stringWithUTF8String:"⌘"];
    SRModifierFlagStringOption = [NSString stringWithUTF8String:"⌥"];
    SRModifierFlagStringShift = [NSString stringWithUTF8String:"⇧"];
    SRModifierFlagStringControl = [NSString stringWithUTF8String:"⌃"];
}


NSBundle *SRBundle()
{
    static dispatch_once_t onceToken;
    static NSBundle *Bundle = nil;
    dispatch_once(&onceToken, ^{
        NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"ShortcutRecorder_ShortcutRecorder" withExtension:@"bundle"];
        Bundle = bundleURL ? [NSBundle bundleWithURL:bundleURL] : [NSBundle bundleWithIdentifier:@"com.kulakov.ShortcutRecorder"];
    });

    if (Bundle)
        return Bundle;
    else
    {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Unable to find bundle with resources."
                                     userInfo:nil];
    }
}


NSString *SRLoc(NSString *aKey)
{
    return NSLocalizedStringFromTableInBundle(aKey, @"ShortcutRecorder", SRBundle(), nil);
}


NSImage *SRImage(NSString *anImageName)
{
    return [SRBundle() imageForResource:anImageName];
}


@implementation NSObject (SRCommon)

- (BOOL)SR_isEqual:(nullable NSObject *)anObject usingSelector:(SEL)aSelector ofCommonAncestor:(Class)anAncestor
{
    typedef BOOL (*IsEqualTo)(id, SEL, id);

    if (anObject == self)
        return YES;
    else if (!anObject)
        return NO;
    else if ([self isKindOfClass:anObject.class])
        return ((IsEqualTo)[self methodForSelector:aSelector])(self, aSelector, anObject);
    else if ([anObject isKindOfClass:self.class])
        return ((IsEqualTo)[anObject methodForSelector:aSelector])(anObject, aSelector, self);
    else if ([anObject isKindOfClass:anAncestor])
    {
        NSAssert([self isKindOfClass:anAncestor], @"Receiver must be an instance of the specified ancestor.");
        IsEqualTo selfImp = (IsEqualTo)[self methodForSelector:aSelector];
        IsEqualTo objectImp = (IsEqualTo)[anObject methodForSelector:aSelector];

        if (selfImp == objectImp)
            return selfImp(self, aSelector, anObject);
    }

    return NO;
}

@end
