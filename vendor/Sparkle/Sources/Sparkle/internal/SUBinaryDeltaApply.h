//
//  SUBinaryDeltaApply.h
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#ifndef SUBINARYDELTAAPPLY_H
#define SUBINARYDELTAAPPLY_H

#import <Foundation/Foundation.h>

@class NSString;
BOOL applyBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, BOOL verbose, void (^progressCallback)(double), NSError * __autoreleasing *error);

#endif
