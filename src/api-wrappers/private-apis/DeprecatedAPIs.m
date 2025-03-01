//
//  DeprecatedAPIs.m
//  alt-tab-macos
//
//  Created by Zachary Wander on 3/1/25.
//  Copyright © 2025 lwouis. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import "DeprecatedAPIs.h"

@implementation DeprecatedAPIs

+(void)setFrontmost:(ProcessSerialNumber)psn {
    SetFrontProcessWithOptions(&psn, kSetFrontProcessCausedByUser);
}

@end
