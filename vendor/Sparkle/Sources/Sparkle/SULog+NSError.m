//
//  SULog+NSError.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/19/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SULog+NSError.h"
#import "SULog.h"

#include "AppKitPrevention.h"

static void SULogErrors(NSArray<NSError *> *errors, int recursionLimit)
{
    if (recursionLimit == 0) {
        return;
    }
    
    for (NSError *error in errors) {
        SULog(SULogLevelError, @"Error: %@ %@ (URL %@)", error.localizedDescription, error.localizedFailureReason, error.userInfo[NSURLErrorFailingURLErrorKey]);
        
        NSDictionary<NSErrorUserInfoKey, id> *userInfo = error.userInfo;
        
        if (@available(macOS 11.3, *)) {
            NSArray<NSError *> *underlyingErrors = userInfo[NSMultipleUnderlyingErrorsKey];
            if (underlyingErrors != nil) {
                SULogErrors(underlyingErrors, recursionLimit - 1);
                continue;
            }
        }
        
        NSError *underlyingError = userInfo[NSUnderlyingErrorKey];
        if (underlyingError != nil) {
            SULogErrors(@[underlyingError], recursionLimit - 1);
        }
    }
}

void SULogError(NSError *error)
{
    if (error == nil) {
        return;
    }
    
    SULogErrors(@[error], 7);
}
