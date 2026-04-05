//
//  SPUVerifierInformation.m
//  Autoupdate
//
//  Copyright © 2023 Sparkle Project. All rights reserved.
//

#import "SPUVerifierInformation.h"

@implementation SPUVerifierInformation

@synthesize expectedVersion = _expectedVersion;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize actualVersion = _actualVersion;
@synthesize actualContentLength = _actualContentLength;

- (instancetype)initWithExpectedVersion:(NSString *)expectedVersion expectedContentLength:(uint64_t)expectedContentLength
{
    self = [super init];
    if (self != nil) {
        _expectedVersion = [expectedVersion copy];
        _expectedContentLength = expectedContentLength;
    }
    return self;
}

@end
